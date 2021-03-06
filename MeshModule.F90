MODULE MeshModule

  USE RealKindModule, ONLY: &
    Half

  IMPLICIT NONE
  PRIVATE

#include "finclude/petsc.h90"

  PetscInt, PUBLIC, PARAMETER :: &
    X1 = 0, &
    X2 = 1, &
    X3 = 2

  TYPE, PUBLIC :: MeshType
    PetscInt :: &
      nDimensions, &
      StencilWidth
    PetscInt, DIMENSION(:), ALLOCATABLE :: &
      nZones
    PetscReal, DIMENSION(:), ALLOCATABLE :: &
      InnerBoundaries, &
      OuterBoundaries
    DMDAStencilType :: &
      StencilType
    DMDABoundaryType, DIMENSION(:), ALLOCATABLE :: &
      BoundaryType
    DM :: &
      MeshDA, &
      CoordinateDA
    TYPE(PositionsType), POINTER :: &
      Positions
  END TYPE MeshType

  TYPE :: PositionsType
    PetscInt, DIMENSION(3) :: &
      iBX,  & ! Inner Indices of Local Domain
      iWX,  & ! Width of Local Domain
      iEX,  & ! Outer Indices of Local Domain
      iBXG, & ! Inner Indices of Local Ghosted Domain
      iWXG, & ! Width of Local Ghosted Domain
      iEXG    ! Outer Indices of Local Ghosted Domain
    Vec :: &
      InnerEdgeGlobal, &
      CenterGlobal,    &
      OuterEdgeGlobal, &
      InnerEdgeLocal,  &
      CenterLocal,     &
      OuterEdgeLocal
  END TYPE PositionsType

  PUBLIC :: &
    CreateMesh, &
    DestroyMesh

CONTAINS


  SUBROUTINE CreateMesh(M, Comm, Rank, &
               nZones, InnerBoundaries, OuterBoundaries, BoundaryConditions)

    TYPE(MeshType), POINTER :: &
      M
    PetscInt, INTENT(in) :: &
      Comm, &
      Rank
    PetscInt, DIMENSION(:), INTENT(in) :: &
      nZones
    PetscReal, DIMENSION(:), INTENT(in) :: &
      InnerBoundaries, &
      OuterBoundaries
    DMDABoundaryType, DIMENSION(:), INTENT(in) :: &
      BoundaryConditions

    PetscErrorCode :: &
      Error
    PetscInt :: &
      iDim

    M % nDimensions = SIZE(nZones)

    ALLOCATE( M % nZones         (M % nDimensions) )
    ALLOCATE( M % InnerBoundaries(M % nDimensions) )
    ALLOCATE( M % OuterBoundaries(M % nDimensions) )
    ALLOCATE( M % BoundaryType   (M % nDimensions) )

    DO iDim = 1, M % nDimensions
      M % nZones(iDim)          = nZones(iDim)
      M % InnerBoundaries(iDim) = InnerBoundaries(iDim)
      M % OuterBoundaries(iDim) = OuterBoundaries(iDim)
      M % BoundaryType(iDim)    = BoundaryConditions(iDim)
    END DO

    M % StencilWidth = 1
    M % StencilType  = DMDA_STENCIL_STAR

    IF(Rank == 0)THEN
      PRINT*
      PRINT*, "  INFO: Creating Mesh"
      PRINT*, "    Dimensionality = ", M % nDimensions
      PRINT*, "    Stencil Width  = ", M % StencilWidth
      DO iDim = 1, M % nDimensions
        PRINT*, "      iDim, nZones = ", iDim, M % nZones(iDim)
        PRINT*, "        Inner Boundary   = ", M % InnerBoundaries(iDim)
        PRINT*, "        Outer Boundary   = ", M % OuterBoundaries(iDim)
      END DO
    END IF

    SELECT CASE (M % nDimensions)
      CASE (1)

        CALL CreateMesh1D(M, Comm)

      CASE (2)

        CALL CreateMesh2D(M, Comm)

      CASE (3)

        CALL CreateMesh3D(M, Comm)

    END SELECT

    !  Populate Ghost Zones with Coordinates:

    CALL DMGlobalToLocalBegin( &
           M % CoordinateDA, &
           M % Positions % InnerEdgeGlobal, INSERT_VALUES, &
           M % Positions % InnerEdgeLocal, Error)
    CALL DMGlobalToLocalEnd( &
           M % CoordinateDA, &
           M % Positions % InnerEdgeGlobal, INSERT_VALUES, &
           M % Positions % InnerEdgeLocal, Error)

    CALL DMGlobalToLocalBegin( &
           M % CoordinateDA, &
           M % Positions % OuterEdgeGlobal, INSERT_VALUES, &
           M % Positions % OuterEdgeLocal, Error)
    CALL DMGlobalToLocalEnd( &
           M % CoordinateDA, &
           M % Positions % OuterEdgeGlobal, INSERT_VALUES, &
           M % Positions % OuterEdgeLocal, Error)

    CALL DMGlobalToLocalBegin( &
           M % CoordinateDA, &
           M % Positions % CenterGlobal, INSERT_VALUES, &
           M % Positions % CenterLocal, Error)
    CALL DMGlobalToLocalEnd( &
           M % CoordinateDA, &
           M % Positions % CenterGlobal, INSERT_VALUES, &
           M % Positions % CenterLocal, Error)

  END SUBROUTINE CreateMesh


  SUBROUTINE CreateMesh1D(M, Comm)

    TYPE(MeshType), POINTER :: &
      M
    PetscInt, INTENT(in) :: &
      Comm

    PetscErrorCode :: &
      Error
    PetscInt :: &
      iX1
    PetscReal, DIMENSION(1) :: &
      dX
    PetscReal, DIMENSION(:), POINTER :: &
      InnerEdge, &
      OuterEdge, &
      Center

    CALL DMDACreate3D( &
           Comm, &
           M % BoundaryType(1), &
           M % nZones(1), &
           1, M % StencilWidth, &
           PETSC_NULL_INTEGER, &
           M % MeshDA, Error)

    CALL DMDAGetCoordinateDA( &
           M % MeshDA, M % CoordinateDA, Error)

    !  Create vectors to hold coordinate values:

    ALLOCATE(M % Positions)
    CALL CreatePositions(M % Positions, M % nDimensions, M % CoordinateDA)

    !  Fill in coordinate values:

    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % InnerEdgeGlobal, InnerEdge, Error)
    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % OuterEdgeGlobal, OuterEdge, Error)
    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % CenterGlobal,    Center,    Error)

    !  Equidistant mesh for simplicity
    dX = ( M % OuterBoundaries - M % InnerBoundaries ) / REAL( M % nZones )

    DO iX1 = M % Positions % iBX(1), M % Positions % iEX(1)

      InnerEdge(iX1) &
        = M % InnerBoundaries(1) + dX(1) * iX1
      OuterEdge(iX1) &
        = InnerEdge(iX1) + dX(1)
      Center   (iX1) &
        = Half * ( InnerEdge(iX1) &
                   + OuterEdge(iX1) )

    END DO

    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % InnerEdgeGlobal, InnerEdge, Error)
    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % OuterEdgeGlobal, OuterEdge, Error)
    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % CenterGlobal,    Center,    Error)

  END SUBROUTINE CreateMesh1D


  SUBROUTINE CreateMesh2D(M, Comm)

    TYPE(MeshType), POINTER :: &
      M
    PetscInt, INTENT(in) :: &
      Comm

    PetscErrorCode :: &
      Error
    PetscInt :: &
      iX1, iX2
    PetscReal, DIMENSION(2) :: &
      dX
    PetscReal, DIMENSION(:,:,:), POINTER :: &
      InnerEdge, &
      OuterEdge, &
      Center

    CALL DMDACreate2D( &
           Comm, &
           M % BoundaryType(1), M % BoundaryType(2), &
           M % StencilType, &
           M % nZones(1), M % nZones(2), &
           PETSC_DECIDE, PETSC_DECIDE, &
           1, M % StencilWidth, &
           PETSC_NULL_INTEGER, PETSC_NULL_INTEGER, &
           M % MeshDA, Error)

    CALL DMDAGetCoordinateDA( &
           M % MeshDA, M % CoordinateDA, Error)

    !  Create vectors to hold coordinate values:

    ALLOCATE(M % Positions)
    CALL CreatePositions(M % Positions, M % nDimensions, M % CoordinateDA)

    !  Fill in coordinate values:

    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % InnerEdgeGlobal, InnerEdge, Error)
    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % OuterEdgeGlobal, OuterEdge, Error)
    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % CenterGlobal,    Center,    Error)

    !  Equidistant mesh for simplicity
    dX = ( M % OuterBoundaries - M % InnerBoundaries ) / REAL( M % nZones )

    DO iX2 = M % Positions % iBX(2), M % Positions % iEX(2)
      DO iX1 = M % Positions % iBX(1), M % Positions % iEX(1)

        InnerEdge(X1, iX1, iX2) &
          = M % InnerBoundaries(1) + dX(1) * iX1
        OuterEdge(X1, iX1, iX2) &
          = InnerEdge(X1, iX1, iX2) + dX(1)
        Center   (X1, iX1, iX2) &
          = Half * ( InnerEdge(X1, iX1, iX2) &
                     + OuterEdge(X1, iX1, iX2) )

        InnerEdge(X2, iX1, iX2) &
          = M % InnerBoundaries(2) + dX(2) * iX2
        OuterEdge(X2, iX1, iX2) &
          = InnerEdge(X2, iX1, iX2) + dX(2)
        Center   (X2, iX1, iX2) &
          = Half * ( InnerEdge(X2, iX1, iX2) &
                     + OuterEdge(X2, iX1, iX2) )

      END DO
    END DO

    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % InnerEdgeGlobal, InnerEdge, Error)
    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % OuterEdgeGlobal, OuterEdge, Error)
    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % CenterGlobal,    Center,    Error)

  END SUBROUTINE CreateMesh2D


  SUBROUTINE CreateMesh3D(M, Comm)

    TYPE(MeshType), POINTER :: &
      M
    PetscInt, INTENT(in) :: &
      Comm

    PetscErrorCode :: &
      Error
    PetscInt :: &
      iX1, iX2, iX3
    PetscReal, DIMENSION(3) :: &
      dX
    PetscReal, DIMENSION(:,:,:,:), POINTER :: &
      InnerEdge, &
      OuterEdge, &
      Center

    CALL DMDACreate3D( &
           Comm, &
           M % BoundaryType(1), M % BoundaryType(2), M % BoundaryType(3), &
           M % StencilType, &
           M % nZones(1), M % nZones(2), M % nZones(3), &
           PETSC_DECIDE, PETSC_DECIDE, PETSC_DECIDE, &
           1, M % StencilWidth, &
           PETSC_NULL_INTEGER, PETSC_NULL_INTEGER, PETSC_NULL_INTEGER, &
           M % MeshDA, Error)

    CALL DMDAGetCoordinateDA( &
           M % MeshDA, M % CoordinateDA, Error)

    !  Create vectors to hold coordinate values:

    ALLOCATE(M % Positions)
    CALL CreatePositions(M % Positions, M % nDimensions, M % CoordinateDA)

    !  Fill in coordinate values:

    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % InnerEdgeGlobal, InnerEdge, Error)
    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % OuterEdgeGlobal, OuterEdge, Error)
    CALL DMDAVecGetArrayF90( &
           M % CoordinateDA, M % Positions % CenterGlobal,    Center,    Error)

    !  Equidistant mesh for simplicity
    dX = ( M % OuterBoundaries - M % InnerBoundaries ) / REAL( M % nZones )

    DO iX3 = M % Positions % iBX(3), M % Positions % iEX(3)
      DO iX2 = M % Positions % iBX(2), M % Positions % iEX(2)
        DO iX1 = M % Positions % iBX(1), M % Positions % iEX(1)

          InnerEdge(X1, iX1, iX2, iX3) &
            = M % InnerBoundaries(1) + dX(1) * iX1
          OuterEdge(X1, iX1, iX2, iX3) &
            = InnerEdge(X1, iX1, iX2, iX3) + dX(1)
          Center   (X1, iX1, iX2, iX3) &
            = Half * ( InnerEdge(X1, iX1, iX2, iX3) &
                       + OuterEdge(X1, iX1, iX2, iX3) )

          InnerEdge(X2, iX1, iX2, iX3) &
            = M % InnerBoundaries(2) + dX(2) * iX2
          OuterEdge(X2, iX1, iX2, iX3) &
            = InnerEdge(X2, iX1, iX2, iX3) + dX(2)
          Center   (X2, iX1, iX2, iX3) &
            = Half * ( InnerEdge(X2, iX1, iX2, iX3) &
                       + OuterEdge(X2, iX1, iX2, iX3) )

          InnerEdge(X3, iX1, iX2, iX3) &
            = M % InnerBoundaries(3) + dX(3) * iX3
          OuterEdge(X3, iX1, iX2, iX3) &
            = InnerEdge(X3, iX1, iX2, iX3) + dX(3)
          Center   (X3, iX1, iX2, iX3) &
            = Half * ( InnerEdge(X3, iX1, iX2, iX3) &
                       + OuterEdge(X3, iX1, iX2, iX3) )

        END DO
      END DO
    END DO

    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % InnerEdgeGlobal, InnerEdge, Error)
    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % OuterEdgeGlobal, OuterEdge, Error)
    CALL DMDAVecRestoreArrayF90( &
           M % CoordinateDA, M % Positions % CenterGlobal,    Center,    Error)

  END SUBROUTINE CreateMesh3D


  SUBROUTINE CreatePositions(Positions, nDimensions, CoordinateDA)

    TYPE(PositionsType), POINTER :: &
      Positions
    PetscInt :: &
      nDimensions
    DM :: &
      CoordinateDA

    PetscErrorCode :: &
      Error
    PetscInt :: &
      iDim

    ! Global (Non-Ghosted) Position Vectors:

    CALL DMCreateGlobalVector( &
           CoordinateDA,                Positions % InnerEdgeGlobal, Error)
    CALL VecDuplicate( &
           Positions % InnerEdgeGlobal, Positions % CenterGlobal,    Error)
    CALL VecDuplicate( &
           Positions % InnerEdgeGlobal, Positions % OuterEdgeGlobal, Error)

    Positions % iBX(:) = 0
    Positions % iWX(:) = 1
    Positions % iEX(:) = 0

    ! Get Indices for Non-Ghosted Vectors:

    SELECT CASE (nDimensions)
      CASE (1)
        CALL DMDAGetCorners( &
               CoordinateDA, &
               Positions % iBX(1), PETSC_NULL_INTEGER, PETSC_NULL_INTEGER, &
               Positions % iWX(1), PETSC_NULL_INTEGER, PETSC_NULL_INTEGER, &
               Error)

      CASE (2)
        CALL DMDAGetCorners( &
               CoordinateDA, &
               Positions % iBX(1), Positions % iBX(2), PETSC_NULL_INTEGER, &
               Positions % iWX(1), Positions % iWX(2), PETSC_NULL_INTEGER, &
               Error)

      CASE(3)
        CALL DMDAGetCorners( &
               CoordinateDA, &
               Positions % iBX(1), Positions % iBX(2), Positions % iBX(3), &
               Positions % iWX(1), Positions % iWX(2), Positions % iWX(3), &
               Error)

    END SELECT

    DO iDim = 1, nDimensions
      Positions % iEX(iDim) &
        = Positions % iBX(iDim) &
            + Positions % iWX(iDim) - 1
    END DO

    !  Local (Ghosted) Position Vectors:

    CALL DMCreateLocalVector( &
           CoordinateDA,               Positions % InnerEdgeLocal, Error)
    CALL VecDuplicate( &
           Positions % InnerEdgeLocal, Positions % CenterLocal,    Error)
    CALL VecDuplicate( &
           Positions % InnerEdgeLocal, Positions % OuterEdgeLocal, Error)

    Positions % iBXG(:) = 0
    Positions % iWXG(:) = 1
    Positions % iEXG(:) = 0

    !  Get Indices for Ghosted Vectors:

    SELECT CASE (nDimensions)
      CASE (1)
        CALL DMDAGetGhostCorners( &
               CoordinateDA, &
               Positions % iBXG(1), PETSC_NULL_INTEGER, PETSC_NULL_INTEGER, &
               Positions % iWXG(1), PETSC_NULL_INTEGER, PETSC_NULL_INTEGER, &
               Error)

      CASE (2)
        CALL DMDAGetGhostCorners( &
               CoordinateDA, &
               Positions % iBXG(1), Positions % iBXG(2), PETSC_NULL_INTEGER, &
               Positions % iWXG(1), Positions % iWXG(2), PETSC_NULL_INTEGER, &
               Error)

      CASE (3)
        CALL DMDAGetGhostCorners( &
               CoordinateDA, &
               Positions % iBXG(1), Positions % iBXG(2), Positions % iBXG(3), &
               Positions % iWXG(1), Positions % iWXG(2), Positions % iWXG(3), &
               Error)

    END SELECT

    DO iDim = 1, nDimensions
      Positions % iEXG(iDim) &
        = Positions % iBXG(iDim) &
            + Positions % iWXG(iDim) - 1
    END DO

  END SUBROUTINE CreatePositions


  SUBROUTINE DestroyMesh(M)

    TYPE(MeshType), POINTER :: &
      M

    PetscErrorCode :: &
      Error

    DEALLOCATE( M % nZones )
    DEALLOCATE( M % InnerBoundaries )
    DEALLOCATE( M % OuterBoundaries )
    DEALLOCATE( M % BoundaryType )

    CALL DestroyPositions(M % Positions)
    DEALLOCATE(M % Positions)

    CALL DMDestroy(M % MeshDA, Error)

  END SUBROUTINE DestroyMesh


  SUBROUTINE DestroyPositions(Positions)

    TYPE(PositionsType), POINTER :: &
      Positions

    PetscErrorCode :: &
      Error

    CALL VecDestroy(Positions % InnerEdgeGlobal, Error)
    CALL VecDestroy(Positions % CenterGlobal,    Error)
    CALL VecDestroy(Positions % OuterEdgeGlobal, Error)

    CALL VecDestroy(Positions % InnerEdgeLocal, Error)
    CALL VecDestroy(Positions % CenterLocal,    Error)
    CALL VecDestroy(Positions % OuterEdgeLocal, Error)

  END SUBROUTINE DestroyPositions


END MODULE MeshModule
