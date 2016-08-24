module Dungeon.DungeonGenerator exposing (..)

import AStar exposing (findPath, Position)
import Dungeon.Rooms.Config as Config exposing (..)
import Dungeon.Rooms.Type exposing (..)
import Dice exposing (..)
import Dict exposing (..)
import Dungeon.Room as Room exposing (..)
import List.Extra exposing (lift2)
import Random exposing (..)
import Random.Extra exposing (..)
import Set exposing (..)
import Tile exposing (..)
import Utils.Vector as Vector exposing (..)


type alias Model =
    { config : Config.Model
    }


type alias Map =
    Dict Vector Tile


type alias Tiles =
    List Tile


type alias Rooms =
    List Room


type alias DungeonRooms =
    List DungeonRoom


type alias DungeonRoom =
    { position : Vector
    , room : Room
    }


init : Model
init =
    { config = Config.init
    }


generate : Config.Model -> Generator Map
generate config =
    let
        toKVPair tile =
            ( tile.position, tile )

        roomsToTileGenerator rooms =
            rooms
                |> roomsToTiles
                |> Random.Extra.constant

        tilesToMapGenerator tiles =
            tiles
                |> List.map toKVPair
                |> Dict.fromList
                |> Random.Extra.constant
    in
        generateDungeonRooms config config.nRooms []
            `andThen` roomsToTileGenerator
            `andThen` tilesToMapGenerator


generateDungeonRooms : Config.Model -> Int -> DungeonRooms -> Generator DungeonRooms
generateDungeonRooms config num dungeonRooms =
    let
        recurse dungeonRoom =
            generateDungeonRooms config (num - 1) (dungeonRoom :: dungeonRooms)
    in
        if num == 0 then
            Random.Extra.constant dungeonRooms
        else
            Room.generate config
                `andThen` (\room -> roomToDungeonRoom room config)
                `andThen` recurse


roomToDungeonRoom : Room -> Config.Model -> Generator DungeonRoom
roomToDungeonRoom room { dungeonSize } =
    (Dice.d2d dungeonSize dungeonSize)
        `andThen` (\pos -> Random.Extra.constant (DungeonRoom pos room))


roomsToTiles : DungeonRooms -> Tiles
roomsToTiles dungeonRooms =
    let
        roomsToTiles room =
            roomToTiles room.room room.position

        tiles =
            dungeonRooms
                |> List.map roomsToTiles
                |> List.concat

        defaultPosition =
            \x -> Maybe.withDefault ( 0, 0 ) x

        --path =
        --    connectRooms ( room1, defaultPosition <| List.head startPositions )
        --        ( room2, defaultPosition <| List.head <| List.drop 1 startPositions )
        --        map
        --corridor =
        --    case path of
        --        Nothing ->
        --            []
        --        Just realPath ->
        --            List.map (\x -> Tile.toTile x Tile.DarkDgn) realPath
        --roomsWithCorridors =
        --    Dict.fromList (List.map toKVPair (corridor ++ tiles))
        --filledMap =
        --    fillWithWall roomsWithCorridors
    in
        tiles


fillWithWall : Dict Vector Tile -> List Tile
fillWithWall partialMap =
    let
        addWallIfTileDoesNotExist =
            \x y ->
                case Dict.get ( x, y ) partialMap of
                    Nothing ->
                        Tile.toTile ( x, y ) Tile.Rock

                    Just tile ->
                        tile

        dungeonSize =
            .dungeonSize Config.init
    in
        List.Extra.lift2 addWallIfTileDoesNotExist [0..dungeonSize] [0..dungeonSize]


roomToTiles : Room -> Vector -> List Tile
roomToTiles room startPos =
    let
        toWorldPos localPos =
            Vector.add startPos localPos

        items =
            [ ( Tile.DarkDgn, room.floors ), ( Tile.Rock, List.concat room.walls ), ( Tile.Rock, room.corners ) ]

        makeTiles ( tileType, positions ) =
            positions
                |> List.map toWorldPos
                |> List.map (\pos -> Tile.toTile pos tileType)
    in
        List.concat (List.map makeTiles items)
            ++ List.map
                (\( entrance, pos ) ->
                    Tile.toTile (toWorldPos pos) (entranceToTileType entrance)
                )
                room.doors



--generateRooms : Int -> ( Int, List DungeonRoom, Random.Seed ) -> ( List DungeonRoom, Random.Seed )
--generateRooms nRooms ( retries, rooms, seed ) =
--    case ( nRooms, retries ) of
--        ( 0, _ ) ->
--            ( rooms, seed )
--        ( _, 0 ) ->
--            ( rooms, seed )
--        ( n, _ ) ->
--            let
--                ( room, seed' ) =
--                    Room.generate seed
--                ( pos, seed'' ) =
--                    Dice.roll2D 30 seed'
--            in
--                if overlapsRooms room pos rooms then
--                    generateRooms n ( (retries - 1), rooms, seed'' )
--                else
--                    generateRooms (n - 1) ( (retries - 1), (DungeonRoom pos room) :: rooms, seed'' )


removeOverlaps : DungeonRooms -> Generator DungeonRooms
removeOverlaps rooms =
    let
        overlapFolder room rooms =
            case isOverlapping room rooms of
                True ->
                    let
                        _ =
                            Debug.log "rejected" room
                    in
                        rooms

                False ->
                    let
                        _ =
                            Debug.log "accepted" room
                    in
                        room :: rooms
    in
        Random.Extra.constant <| List.foldl overlapFolder [] rooms


isOverlapping : DungeonRoom -> List DungeonRoom -> Bool
isOverlapping room rooms =
    let
        end room =
            Vector.add room.position room.room.dimension

        roomStart =
            room.position

        roomEnd =
            end room
    in
        case rooms of
            [] ->
                False

            firstRoom :: xs ->
                let
                    firstRoomStart =
                        firstRoom.position

                    firstRoomEnd =
                        Vector.add firstRoom.position firstRoom.room.dimension

                    intersects =
                        { startX = Vector.boxIntersectXAxis (fst roomStart) ( firstRoomStart, firstRoomEnd )
                        , endX = Vector.boxIntersectXAxis (fst roomEnd) ( firstRoomStart, firstRoomEnd )
                        , startY = Vector.boxIntersectYAxis (snd roomStart) ( firstRoomStart, firstRoomEnd )
                        , endY = Vector.boxIntersectYAxis (snd roomEnd) ( firstRoomStart, firstRoomEnd )
                        }
                in
                    if (intersects.startX || intersects.endX) && (intersects.startY || intersects.endY) then
                        True
                    else
                        isOverlapping room xs


entranceToTileType : Entrance -> Tile.TileType
entranceToTileType entrance =
    case entrance of
        Door ->
            Tile.DoorClosed

        --BrokenDoor ->
        --    Tile.DoorBroken
        NoDoor ->
            Tile.DarkDgn


connectRooms : ( Room, Vector ) -> ( Room, Vector ) -> Dict Vector Tile -> Maybe AStar.Path
connectRooms ( r1, r1Offset ) ( r2, r2Offset ) map =
    case ( r1.doors, r2.doors ) of
        ( [], _ ) ->
            Nothing

        ( _, [] ) ->
            Nothing

        ( ( _, start ) :: _, ( _, end ) :: _ ) ->
            AStar.findPath heuristic
                (neighbours map)
                (Vector.add start r1Offset)
                (Vector.add end r2Offset)



--------------------------
-- Corridor pathfinding --
--------------------------


heuristic : Vector -> Vector -> Float
heuristic start end =
    let
        ( dx, dy ) =
            Vector.sub start end
    in
        toFloat (max dx dy)


neighbours : Dict Vector Tile -> Vector -> Set Position
neighbours map position =
    let
        dungeonSize =
            .dungeonSize Config.init

        add x y =
            Vector.add position ( x, y )

        possibleNeighbours vector =
            [ add -1 -1, add 0 -1, add 1 -1 ]
                ++ [ add -1 0, add 1 0 ]
                ++ [ add -1 1, add 0 1, add 1 1 ]

        isOutOfBounds ( x, y ) =
            if x > dungeonSize || y > dungeonSize then
                True
            else if x < 0 || y < 0 then
                True
            else
                False

        isObstructed (( x, y ) as vector) =
            if isOutOfBounds vector then
                True
            else
                case Dict.get vector map of
                    Just tile ->
                        Tile.isSolid tile

                    Nothing ->
                        False
    in
        position
            |> possibleNeighbours
            |> List.filter (\x -> not <| isObstructed x)
            |> Set.fromList