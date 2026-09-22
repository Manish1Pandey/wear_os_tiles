/// Wear OS Tiles and watch-face Complications for Flutter.
///
/// Describe a tile with [TileLayout] and push it with
/// [WearTiles.updateTile]; push complication values with
/// [WearComplications.update]. Generic Kotlin services bundled with the
/// plugin render the stored descriptions whenever Wear OS asks.
library;

export 'src/complication_data.dart';
export 'src/tile_layout.dart'
    show
        ArcLine,
        ArcSpacer,
        ArcStrokeCap,
        ArcText,
        TileAction,
        TileActionType,
        TileArc,
        TileArcAnchor,
        TileArcElement,
        TileBox,
        TileButton,
        TileChip,
        TileCircularProgress,
        TileColumn,
        TileComponentStyle,
        TileContentScale,
        TileDimension,
        TileDimensionKind,
        TileElement,
        TileFontWeight,
        TileHorizontalAlignment,
        TileImage,
        TileLayout,
        TileLayoutException,
        TileModifiers,
        TilePadding,
        TileRow,
        TileSpacer,
        TileText,
        TileTextAlign,
        TileVerticalAlignment,
        isValidWearId,
        maxTileLayoutDepth,
        tileWireFormatVersion;
export 'src/wear_os_tiles_api.dart';
