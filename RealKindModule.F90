MODULE RealKindModule

  IMPLICIT NONE
  PRIVATE

  INTEGER, PUBLIC, PARAMETER :: &
    RealKind = KIND(1.d0)

  REAL(kind=RealKind), PUBLIC, PARAMETER :: &
    Zero  = 0.0_RealKind, &
    One   = 1.0_RealKind, &
    Two   = 2.0_RealKind, &
    Three = 3.0_RealKind, &
    Four  = 4.0_RealKind, &
    Five  = 5.0_RealKind, &
    Six   = 6.0_RealKind, &
    Seven = 7.0_RealKind, &
    Eight = 8.0_RealKind, &
    Nine  = 9.0_RealKind

  REAL(kind=RealKind), PUBLIC, PARAMETER :: &
    Half = 0.5_RealKind

  REAL(kind=RealKind), PUBLIC, PARAMETER :: &
    Tiny = 1.0E-16_RealKind, &
    Huge = 1.0E+16_RealKind

  REAL(kind=RealKind), PUBLIC, PARAMETER :: &
    Pi = 3.14159265358979323846_RealKind

END MODULE RealKindModule
