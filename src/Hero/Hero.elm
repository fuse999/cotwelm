module Hero.Hero
    exposing
        ( Hero
        , init
        , view
        , move
        , teleport
        , position
        , stats
        , setStats
        , viewStats
        , updateEquipment
        , pickup
        , equip
        )

import Html.Attributes exposing (..)
import Html exposing (..)
import Utils.Vector as Vector exposing (..)
import Utils.Direction as Direction exposing (Direction)
import Stats exposing (Stats)
import Attributes exposing (Attributes)
import Equipment exposing (Equipment, EquipmentSlot)
import GameData.Types as Data
import Utils.Lib as Lib
import Item.Item as Item exposing (Item)
import Types
import Item.Purse as Purse exposing (Purse)


type alias Hero =
    { name : Name
    , type_ : Types.CreatureType
    , position : Vector
    , stats : Stats
    , gender : Data.Gender
    , attributes : Attributes
    , equipment : Equipment
    , expLevel : Int
    , bodySize : Types.BodySize
    }


type alias Name =
    String


init : Name -> Attributes -> Data.Gender -> Hero
init name ({ str, int, con } as attributes) gender =
    { name = name
    , type_ = Types.Hero
    , position = ( 11, 17 )
    , stats = Stats.init attributes
    , gender = gender
    , attributes = attributes
    , equipment = Equipment.init
    , expLevel = 1
    , bodySize = Types.Medium
    }


updateEquipment : Equipment -> Hero -> Hero
updateEquipment equipment model =
    { model | equipment = equipment }


move : Direction -> Hero -> Hero
move direction model =
    direction
        |> Vector.fromDirection
        |> Vector.add model.position
        |> \x -> { model | position = x }


teleport : Vector -> Hero -> Hero
teleport newPosition model =
    { model | position = newPosition }


position : Hero -> Vector
position model =
    model.position


stats : Hero -> Stats
stats model =
    model.stats


setStats : Stats -> Hero -> Hero
setStats stats model =
    { model | stats = stats }


pickupCoins : Purse.Coins -> Hero -> Hero
pickupCoins coins hero =
    let
        purse =
            Equipment.getPurse hero.equipment
                |> Maybe.withDefault Purse.init
                |> Purse.addCoins coins

        equipment =
            Equipment.setPurse purse hero.equipment
    in
        { hero | equipment = equipment }



-- Equipment


pickup : Item -> Hero -> (Hero, Equipment.Msg)
pickup item hero =
    case item of
        Item.ItemCopper { value } ->
            (pickupCoins (Purse.Coins value 0 0 0) hero, Equipment.Success)

        Item.ItemSilver { value } ->
            (pickupCoins (Purse.Coins 0 value 0 0) hero, Equipment.Success)

        Item.ItemGold { value } ->
            (pickupCoins (Purse.Coins 0 0 value 0) hero, Equipment.Success)

        Item.ItemPlatinum { value } ->
            (pickupCoins (Purse.Coins 0 0 0 value) hero, Equipment.Success)

        _ ->
            let
                ( equipment_, msg ) =
                    Equipment.putInPack item hero.equipment
            in
                ({ hero | equipment = equipment_ }, msg)


equip : ( EquipmentSlot, Item ) -> Hero -> Result Equipment.Msg Hero
equip ( slot, item ) model =
    Equipment.equip ( slot, item ) model.equipment
        |> Result.map (\equipment -> { model | equipment = equipment })



-- View


view : Hero -> Html a
view model =
    let
        heroCss =
            if model.gender == Data.Male then
                "male-hero"
            else
                "female-hero"
    in
        div [ class ("tile " ++ heroCss), Lib.vectorToHtmlStyle <| model.position ] []


viewStats : Hero -> Html a
viewStats model =
    div []
        [ div [] [ text "Stats:" ]
        , div [] [ text <| "HP: " ++ (Stats.printHP model.stats) ]
        , div [] [ text <| "SP: " ++ (Stats.printSP model.stats) ]
        ]
