module Dungeon.Rooms.Type exposing (..)

import Utils.Vector exposing (..)
import Dungeon.Entrance exposing (..)


type RoomType
    = Rectangular
    | Cross
    | Diamond
    | Potion
    | Circular
    | DiagonalSquares
    | DeadEnd


type alias Dimension =
    Vector


type alias Wall =
    Vector


type alias Walls =
    List Wall


type alias Floors =
    List Vector


type alias RoomSize =
    Int


type alias Room =
    { entrances : Entrances
    , walls : List Walls
    , floors : Floors
    , corners : Walls
    , roomType : RoomType
    , dimension : Dimension
    }


type alias Rooms =
    List Room


type alias RoomTemplate =
    { makeWalls : Dimension -> List Walls
    , makeCorners : Dimension -> Walls
    , makeFloors : Dimension -> Floors
    }
