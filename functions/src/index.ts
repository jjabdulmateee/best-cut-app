/**
 * Best Cut — Cloud Functions
 * 
 * Phase 4: Smart Rerouting + Timeout Handling
 * 
 * Scheduled function: checkExpiredAssignments
 *   - Runs every 1 minute
 *   - Finds bookings where status=pending AND assignmentExpiresAt < now
 *   - Marks assignmentExpired = true
 *   - Increments barber's ignoredAssignmentsCount
 *   - Does NOT cancel, does NOT refund, escrow stays untouched
 *   - Customer app detects flag and shows reroute/cancel options
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();

// ============================================================================
// SCHEDULED FUNCTION: checkExpiredAssignments
// Runs every 1 minute via Cloud Scheduler
// ============================================================================

export const checkExpiredAssignments = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    try {
      // Find all pending bookings whose assignment has expired
      const expiredSnap = await db
        .collection("bookings")
        .where("status", "==", "pending")
        .where("assignmentExpired", "==", false)
        .where("assignmentExpiresAt", "<=", now)
        .get();

      if (expiredSnap.empty) {
        console.log("checkExpiredAssignments: No expired assignments found.");
        return null;
      }

      console.log(
        `checkExpiredAssignments: Found ${expiredSnap.size} expired assignment(s).`
      );

      const batch = db.batch();
      const barberIgnoreCounts: Record<string, number> = {};

      for (const doc of expiredSnap.docs) {
        const data = doc.data();
        const barberId = data.barberId as string;
        const bookingId = doc.id;

        // Mark assignment as expired — DO NOT cancel, DO NOT refund
        batch.update(doc.ref, {
          assignmentExpired: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Track barber ignore count
        barberIgnoreCounts[barberId] =
          (barberIgnoreCounts[barberId] || 0) + 1;

        console.log(
          `  Booking ${bookingId}: assignment expired (barber: ${barberId})`
        );

        // Send FCM notification to customer (if token exists)
        const customerId = data.customerId as string;
        if (customerId) {
          try {
            const customerDoc = await db
              .collection("users")
              .doc(customerId)
              .get();
            const fcmToken = customerDoc.data()?.fcmToken as string | undefined;

            if (fcmToken) {
              await admin.messaging().send({
                token: fcmToken,
                notification: {
                  title: "Barber didn't respond",
                  body: "The barber didn't respond in time. What would you like to do?",
                },
                data: {
                  type: "assignment_expired",
                  bookingId: bookingId,
                },
              });
              console.log(`  FCM sent to customer ${customerId}`);
            }
          } catch (fcmErr) {
            // FCM failure is non-critical — customer will see it on app open
            console.warn(`  FCM failed for customer ${customerId}:`, fcmErr);
          }
        }
      }

      // Commit all booking updates
      await batch.commit();

      // Update barber ignoredAssignmentsCount (admin visibility only)
      for (const [barberId, count] of Object.entries(barberIgnoreCounts)) {
        try {
          await db
            .collection("users")
            .doc(barberId)
            .update({
              ignoredAssignmentsCount:
                admin.firestore.FieldValue.increment(count),
            });
          console.log(
            `  Barber ${barberId}: ignoredAssignmentsCount += ${count}`
          );
        } catch (err) {
          console.warn(`  Failed to update ignoredCount for ${barberId}:`, err);
        }
      }

      console.log(
        `checkExpiredAssignments: Processed ${expiredSnap.size} booking(s).`
      );
      return null;
    } catch (err) {
      console.error("checkExpiredAssignments FAILED:", err);
      return null;
    }
  });

// ============================================================================
// CALLABLE: rerouteBooking
// Called by customer when they choose "Find Another Barber"
// Updates the booking document — same booking ID, different barber
// ============================================================================

export const rerouteBooking = functions.https.onCall(async (data, context) => {
  // Auth check
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Must be signed in."
    );
  }

  const { bookingId, newBarberId } = data;

  if (!bookingId || !newBarberId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "bookingId and newBarberId are required."
    );
  }

  const bookingRef = db.collection("bookings").doc(bookingId);

  return db.runTransaction(async (transaction) => {
    const bookingSnap = await transaction.get(bookingRef);

    if (!bookingSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Booking not found.");
    }

    const booking = bookingSnap.data()!;

    // Validate caller is the customer
    if (booking.customerId !== context.auth!.uid) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only the booking customer can reroute."
      );
    }

    // Must be pending + expired
    if (booking.status !== "pending") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Booking must be in pending status to reroute."
      );
    }

    if (!booking.assignmentExpired) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Assignment has not expired yet."
      );
    }

    // Max 3 reroutes
    const currentRerouteCount = (booking.rerouteCount as number) || 0;
    if (currentRerouteCount >= 3) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Maximum reroute limit (3) reached. Please cancel for a refund."
      );
    }

    // Cannot reroute to the same barber
    if (booking.barberId === newBarberId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Cannot reroute to the same barber."
      );
    }

    // Fetch new barber info
    const newBarberSnap = await transaction.get(
      db.collection("users").doc(newBarberId)
    );

    if (!newBarberSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "New barber not found."
      );
    }

    const newBarber = newBarberSnap.data()!;

    // Validate new barber is approved and online
    if (newBarber.status !== "approved") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Selected barber is not approved."
      );
    }

    // Calculate new expiry (30 minutes from now)
    const now = admin.firestore.Timestamp.now();
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + 30 * 60 * 1000
    );

    // Update the SAME booking document — no new booking created
    transaction.update(bookingRef, {
      // New barber assignment
      barberId: newBarberId,
      barberName: newBarber.name || "Barber",
      shopName: newBarber.shopName || null,
      barberImageUrl: newBarber.imageUrl || "",
      barberAddress: newBarber.address || null,

      // Assignment tracking
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      assignmentExpiresAt: expiresAt,
      assignmentExpired: false,
      rerouteCount: currentRerouteCount + 1,
      lastAssignmentBarberId: booking.barberId,

      // Keep status pending — new barber must accept
      status: "pending",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      message: `Booking rerouted to ${newBarber.name || "new barber"}. They have 30 minutes to respond.`,
      newBarberId: newBarberId,
      rerouteCount: currentRerouteCount + 1,
    };
  });
});

// ============================================================================
// TRIGGER: onBookingAccepted
// When a barber accepts, clear the assignment expiry
// ============================================================================

export const onBookingStatusChange = functions.firestore
  .document("bookings/{bookingId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // When status changes from pending to confirmed (accepted)
    if (before.status === "pending" && after.status === "confirmed") {
      // Clear assignment expiry — barber responded in time
      await change.after.ref.update({
        assignmentExpired: false,
        // Keep assignedAt and assignmentExpiresAt for audit trail
      });
      console.log(
        `Booking ${context.params.bookingId}: accepted, assignment expiry cleared.`
      );
    }

    // When barber cancels after accepting — treat like timeout
    if (
      before.status === "confirmed" &&
      after.status === "cancelledByBarber"
    ) {
      // Mark as expired so customer sees reroute options
      await change.after.ref.update({
        status: "pending",
        assignmentExpired: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Increment barber ignore count
      const barberId = before.barberId as string;
      if (barberId) {
        await db
          .collection("users")
          .doc(barberId)
          .update({
            ignoredAssignmentsCount:
              admin.firestore.FieldValue.increment(1),
          });
      }

      console.log(
        `Booking ${context.params.bookingId}: barber cancelled after accepting — reverted to pending+expired.`
      );
    }
  });
