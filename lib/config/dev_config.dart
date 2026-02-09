/// ============================================================================
/// DEV MODE CONFIGURATION
/// ============================================================================
/// 
/// This file contains feature flags for development mode.
/// These flags allow us to bypass certain production features during development
/// while keeping the underlying infrastructure intact for production launch.
/// 
/// IMPORTANT: Review all flags in this file before production deployment.
/// ============================================================================

// ──────────────────────────────────────────────────────────────────────────────
// BARBER APPROVAL GATING
// ──────────────────────────────────────────────────────────────────────────────
/// Controls whether barbers must complete document verification and admin approval
/// before accessing barber features.
///
/// When ENABLED (true):
///  - Barbers sign up with status = 'draft'
///  - Must upload CNIC, profile photo, 4 shop photos
///  - Status auto-changes to 'submitted' when documents complete
///  - Admin reviews and sets status to 'approved' / 'rejected' / 'needMoreDocs'
///  - Only 'approved' barbers can access barber features
///  - Unapproved barbers see BarberApplicationStatusScreen (document portal)
///
/// When DISABLED (false) — DEV MODE:
///  - Barbers sign up with status = 'approved' (instant access)
///  - BarberApplicationStatusScreen is bypassed
///  - Document upload requirement is skipped
///  - Barber application document is still created (for data integrity)
///  - Firestore rules remain unchanged (ready for production)
///
/// ⚠️ SET TO `true` BEFORE PRODUCTION LAUNCH ⚠️
const bool ENABLE_BARBER_APPROVAL = false;
