import 'dart:ui';

/// Where the face is expected on web, which has no face detector: the user
/// lines their face up with a drawn guide and the pulse is read from fixed
/// patches inside it.
///
/// All coordinates are fractions of the square the measuring circle shows.

/// The face outline drawn as the guide.
const faceGuideOval = Rect.fromLTWH(0.24, 0.1, 0.52, 0.76);

/// Forehead, left cheek, right cheek — the same three regions the mobile path
/// places from ML Kit's eye landmarks, so the backend gets the same payload.
const fixedSkinPatches = [
  Rect.fromLTWH(0.38, 0.2, 0.24, 0.09),
  Rect.fromLTWH(0.31, 0.5, 0.12, 0.12),
  Rect.fromLTWH(0.57, 0.5, 0.12, 0.12),
];
