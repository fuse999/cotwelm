module Game.Game
    exposing
        ( Model
        , Msg
        , init
        , update
        , view
        , subscription
        )

import AStar
import Combat
import Dict
import Equipment exposing (Equipment)
import Game.Keyboard as Keyboard exposing (..)
import Game.Maps as Maps
import GameData.Building as Building exposing (Building)
import GameData.Types as GDT exposing (Difficulty)
import Hero.Hero as Hero exposing (Hero)
import Html exposing (..)
import Html.Attributes exposing (class, style)
import Item.Factory as ItemFactory exposing (ItemFactory)
import Item.Item as Item exposing (Item)
import Item.Data exposing (..)
import Level
import Monster.Monster as Monster exposing (Monster)
import Pages.Inventory as Inventory exposing (Inventory)
import Random.Pcg as Random exposing (..)
import Set exposing (Set)
import Shops exposing (Shops)
import Stats exposing (..)
import Task exposing (perform)
import Tile exposing (Tile)
import Utils.Direction as Direction exposing (Direction)
import Utils.IdGenerator as IdGenerator exposing (IdGenerator)
import Utils.Lib as Lib
import Utils.Vector as Vector exposing (Vector)
import Window exposing (Size)
import Container exposing (Container)


type alias Model =
    { name : String
    , hero : Hero
    , maps : Maps.Model
    , currentScreen : Screen
    , shops : Shops
    , idGen : IdGenerator
    , seed : Random.Seed
    , windowSize : Window.Size
    , messages : List String
    , viewport : { x : Int, y : Int }
    , difficulty : Difficulty
    , inventory : Inventory
    }


type Screen
    = MapScreen
    | InventoryScreen
    | BuildingScreen Building


type Msg
    = Keyboard Keyboard.Msg
    | InventoryMsg (Inventory.Msg Inventory.Draggable Inventory.Droppable)
    | MapsMsg Maps.Msg
    | WindowSize Window.Size
    | ClickTile Vector
    | Walk (List Vector)


init : Random.Seed -> Hero -> Difficulty -> ( Model, Cmd Msg )
init seed hero difficulty =
    let
        idGenerator =
            IdGenerator.init

        itemFactory =
            ItemFactory.init

        ( heroWithDefaultEquipment, itemFactoryAfterHeroEquipment ) =
            donDefaultGarb itemFactory hero

        ( shops, itemFactoryAfterShop, seed_ ) =
            Shops.init seed itemFactoryAfterHeroEquipment

        ( leatherArmour, itemFactory_ ) =
            ItemFactory.make (ItemTypeArmour LeatherArmour) itemFactoryAfterShop

        ( maps, mapCmd, seed__ ) =
            Maps.init leatherArmour seed_

        cmd =
            Cmd.batch
                [ Cmd.map MapsMsg mapCmd
                , initialWindowSizeCmd
                ]

        ground =
            getGroundAtHero heroWithDefaultEquipment maps
    in
        ( { name = "A new game"
          , hero = heroWithDefaultEquipment
          , maps = maps
          , currentScreen = MapScreen
          , shops = shops
          , idGen = idGenerator
          , inventory = Inventory.init (Inventory.Ground ground) heroWithDefaultEquipment.equipment
          , seed = seed__
          , messages = [ "Welcome to castle of the winds!" ]
          , difficulty = difficulty
          , windowSize = { width = 640, height = 640 }
          , viewport = { x = 0, y = 0 }
          }
        , cmd
        )


monstersOnLevel : Model -> List Monster
monstersOnLevel model =
    model.maps
        |> Maps.currentLevel
        |> .monsters


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        atHeroPosition =
            (==) model.hero.position

        isOnStairs upOrDownStairs =
            Maps.currentLevel model.maps
                |> upOrDownStairs
                |> Maybe.map .pos
                |> Maybe.map atHeroPosition
    in
        case msg of
            Keyboard (KeyDir dir) ->
                ( model
                    |> moveHero dir
                    |> updateViewportOffset model.hero.position
                    |> (\model -> moveMonsters (monstersOnLevel model) [] model)
                , Cmd.none
                )

            Keyboard Esc ->
                case model.currentScreen of
                    MapScreen ->
                        ( model, Cmd.none )

                    BuildingScreen _ ->
                        update (InventoryMsg <| Inventory.keyboardToInventoryMsg Esc) model

                    InventoryScreen ->
                        update (InventoryMsg <| Inventory.keyboardToInventoryMsg Esc) model

            Keyboard Inventory ->
                let
                    ground =
                        getGroundAtHero model.hero model.maps
                in
                    ( { model
                        | currentScreen = InventoryScreen
                        , inventory = Inventory.init (Inventory.Ground ground) model.hero.equipment
                      }
                    , Cmd.none
                    )

            Keyboard GoUpstairs ->
                case isOnStairs Level.upstairs of
                    Just True ->
                        let
                            map_ =
                                Maps.upstairs model.maps

                            heroAtTopOfStairs =
                                Maps.currentLevel map_
                                    |> Level.downstairs
                                    |> Maybe.map .pos
                                    |> Maybe.map (flip Hero.teleport model.hero)
                                    |> Maybe.withDefault model.hero
                        in
                            ( { model
                                | maps = map_
                                , hero = heroAtTopOfStairs
                                , messages = "You climb back up the stairs" :: model.messages
                              }
                                |> updateViewportOffset model.hero.position
                            , Cmd.none
                            )

                    _ ->
                        ( { model | messages = "You need to be on some stairs!" :: model.messages }
                        , Cmd.none
                        )

            Keyboard GoDownstairs ->
                case isOnStairs Level.downstairs of
                    Just True ->
                        let
                            ( newMap, seed_ ) =
                                Random.step (Maps.downstairs model.maps) model.seed

                            currentLevel =
                                Maps.currentLevel newMap

                            heroAtBottomOfStairs =
                                currentLevel
                                    |> Level.upstairs
                                    |> Debug.log "upstairs"
                                    |> Maybe.map .pos
                                    |> Maybe.map (flip Hero.teleport model.hero)
                                    |> Maybe.withDefault model.hero
                        in
                            ( { model
                                | maps = newMap
                                , hero = heroAtBottomOfStairs
                                , seed = seed_
                                , messages = "You go downstairs" :: model.messages
                              }
                                |> updateViewportOffset model.hero.position
                            , Cmd.none
                            )

                    _ ->
                        ( { model | messages = "You need to be on some stairs!" :: model.messages }
                        , Cmd.none
                        )

            InventoryMsg msg ->
                let
                    ( inventory_, maybeExitValues ) =
                        Inventory.update msg model.inventory
                in
                    case maybeExitValues of
                        Nothing ->
                            ( { model | inventory = inventory_ }, Cmd.none )

                        Just ( equipment, merchant ) ->
                            let
                                modelWithHeroAndInventory =
                                    { model
                                        | inventory = inventory_
                                        , hero = Hero.updateEquipment equipment model.hero
                                        , currentScreen = MapScreen
                                    }
                            in
                                case merchant of
                                    Inventory.Ground container ->
                                        let
                                            tile =
                                                Maps.getTile model.hero.position model.maps
                                                    |> Tile.updateGround container

                                            level_ =
                                                Level.updateTile model.hero.position tile (Maps.currentLevel model.maps)

                                            maps_ =
                                                Maps.updateCurrentLevel level_ model.maps
                                        in
                                            ( { modelWithHeroAndInventory
                                                | maps = maps_
                                              }
                                            , Cmd.none
                                            )

                                    Inventory.Shop shop ->
                                        ( { modelWithHeroAndInventory
                                            | shops = Shops.updateShop shop model.shops
                                          }
                                        , Cmd.none
                                        )

            MapsMsg msg ->
                ( { model | maps = Maps.update msg model.maps }, Cmd.none )

            Keyboard _ ->
                ( model, Cmd.none )

            WindowSize size ->
                ( { model | windowSize = size }, Cmd.none )

            ClickTile targetPosition ->
                let
                    path =
                        findPath model.hero.position targetPosition model
                in
                    update (Walk path) model

            Walk [] ->
                ( model, Cmd.none )

            Walk (x :: xs) ->
                let
                    dir =
                        Vector.sub x model.hero.position
                            |> Vector.toDirection

                    walkRemainingPathTask =
                        Task.succeed xs

                    ( model_, cmds_ ) =
                        update (Keyboard (KeyDir dir)) model
                in
                    ( model_
                    , Cmd.batch
                        [ Task.perform Walk walkRemainingPathTask
                        , cmds_
                        ]
                    )


newMessage : String -> Model -> Model
newMessage msg model =
    { model | messages = msg :: model.messages }



--------------
-- Privates --
--------------


getGroundAtHero : Hero -> Maps.Model -> Container Item
getGroundAtHero hero maps =
    hero.position
        |> flip Maps.getTile maps
        |> Tile.ground



-- Collision


moveHero : Direction -> Model -> Model
moveHero dir ({ hero, seed } as model) =
    let
        heroMoved =
            Hero.move dir hero

        obstructions =
            heroMoved
                |> Hero.position
                |> \newHeroPosition -> queryPosition newHeroPosition model
    in
        case obstructions of
            ( _, _, Just monster, _ ) ->
                attackMonster monster model

            -- entering a building
            ( _, Just building, _, _ ) ->
                enterBuilding building model

            -- path blocked
            ( True, _, _, _ ) ->
                model

            -- path free, moved
            ( False, _, _, _ ) ->
                { model | hero = heroMoved }


updateMonsters : List Monster -> Maps.Model -> Maps.Model
updateMonsters monsters maps =
    Maps.currentLevel maps
        |> (\level -> { level | monsters = monsters })
        |> (\level -> Maps.updateCurrentLevel level maps)


attackMonster : Monster -> Model -> Model
attackMonster monster ({ hero, seed, messages, maps } as model) =
    let
        monsters =
            monstersOnLevel model

        ( ( msg, monsterAfterBeingHit ), seed_ ) =
            Random.step (Combat.attack hero monster) seed

        monstersAfterHit monster =
            if Stats.isDead monster.stats then
                Monster.remove monster monsters
            else
                Monster.update monster monsters
    in
        { model
            | seed = seed_
            , maps = updateMonsters (monstersAfterHit monsterAfterBeingHit) model.maps
            , messages = msg :: messages
        }


moveMonsters : List Monster -> List Monster -> Model -> Model
moveMonsters monsters movedMonsters ({ hero, maps, seed } as model) =
    case monsters of
        [] ->
            { model | maps = updateMonsters movedMonsters maps }

        monster :: restOfMonsters ->
            let
                movedMonster =
                    pathMonster monster hero model

                obstructions =
                    queryPosition movedMonster.position model

                isObstructedByMovedMonsters =
                    isMonsterObstruction movedMonster movedMonsters
            in
                case obstructions of
                    -- hit hero
                    ( _, _, _, True ) ->
                        model
                            |> attackHero monster
                            |> moveMonsters restOfMonsters (monster :: movedMonsters)

                    ( True, _, _, _ ) ->
                        moveMonsters restOfMonsters (monster :: movedMonsters) model

                    ( _, Just _, _, _ ) ->
                        moveMonsters restOfMonsters (monster :: movedMonsters) model

                    ( _, _, Just _, _ ) ->
                        moveMonsters restOfMonsters (monster :: movedMonsters) model

                    _ ->
                        if isObstructedByMovedMonsters then
                            moveMonsters restOfMonsters (monster :: movedMonsters) model
                        else
                            moveMonsters restOfMonsters (movedMonster :: movedMonsters) model


attackHero : Monster -> Model -> Model
attackHero monster ({ hero, seed, messages } as model) =
    let
        ( ( msg, heroAfterHit ), seed_ ) =
            Random.step (Combat.attack monster hero) seed
    in
        { model
            | messages = msg :: messages
            , hero = heroAfterHit
            , seed = seed_
        }


enterBuilding : Building -> Model -> Model
enterBuilding building ({ hero, maps } as model) =
    let
        modelWithHeroMoved =
            { model | hero = Hero.teleport building.pos hero }
    in
        case Building.buildingType building of
            Building.Linked link ->
                { model
                    | maps = Maps.updateArea link.area maps
                    , hero = Hero.teleport link.pos hero
                }

            Building.Shop shopType ->
                { model
                    | currentScreen = BuildingScreen building
                    , inventory = Inventory.init (Inventory.Shop <| Shops.shop shopType model.shops) hero.equipment
                }

            Building.Ordinary ->
                { model | currentScreen = BuildingScreen building }

            Building.StairUp ->
                modelWithHeroMoved

            Building.StairDown ->
                modelWithHeroMoved


{-| Given a position and a map, work out everything on the square
-}
queryPosition : Vector -> Model -> ( Bool, Maybe Building, Maybe Monster, Bool )
queryPosition pos ({ hero, maps } as model) =
    let
        monsters =
            monstersOnLevel model

        maybeTile =
            maps
                |> Maps.currentLevel
                |> Level.getTile pos

        level =
            Maps.currentLevel maps

        maybeBuilding =
            buildingAtPosition pos level.buildings

        maybeMonster =
            monsters
                |> List.filter (\x -> pos == x.position)
                |> List.head

        hasHero =
            (Hero.position hero) == pos

        tileObstruction =
            case maybeTile of
                Just tile ->
                    Tile.isSolid tile

                Nothing ->
                    True
    in
        ( tileObstruction, maybeBuilding, maybeMonster, hasHero )


{-| Given a point and a list of buildings, return the building that the point is within or nothing
-}
buildingAtPosition : Vector -> List Building -> Maybe Building
buildingAtPosition pos buildings =
    let
        buildingsAtTile =
            List.filter (Building.isBuildingAtPosition pos) buildings
    in
        case buildingsAtTile of
            b :: rest ->
                Just b

            _ ->
                Nothing



-----------------
-- Pathfinding --
-----------------


findPath : Vector -> Vector -> Model -> List Vector
findPath from to model =
    let
        path =
            AStar.findPath heuristic (neighbours model) from to
    in
        case path of
            Just path ->
                path

            _ ->
                []


pathMonster : Monster -> Hero -> Model -> Monster
pathMonster monster hero model =
    case findPath monster.position hero.position model of
        x :: _ ->
            { monster | position = x }

        _ ->
            monster


{-| Manhattan but counts diagonal cost as one (since you can move diagonally)
-}
heuristic : Vector -> Vector -> Float
heuristic start end =
    let
        ( dx, dy ) =
            Vector.sub start end
    in
        toFloat (max dx dy)


neighbours : Model -> Vector -> Set Vector
neighbours model position =
    let
        add x y =
            Vector.add position ( x, y )

        notObstructed vector =
            not (isObstructed vector model)
    in
        position
            |> Vector.neighbours
            |> List.filter notObstructed
            |> Set.fromList


isObstructed : Vector -> Model -> Bool
isObstructed position model =
    case queryPosition position model of
        ( _, _, _, True ) ->
            False

        ( False, Nothing, Nothing, _ ) ->
            False

        _ ->
            True


isMonsterObstruction : Monster -> List Monster -> Bool
isMonsterObstruction monster monsters =
    let
        atMonsterPosition pos =
            pos == monster.position
    in
        monsters
            |> List.map .position
            |> List.any atMonsterPosition



-----------
-- Adhoc --
-----------


updateViewportOffset : Vector -> Model -> Model
updateViewportOffset prevPosition ({ windowSize, viewport, maps, hero } as model) =
    let
        tileSize =
            32

        ( prevX, prevY ) =
            Vector.scale tileSize prevPosition

        ( curX, curY ) =
            Vector.scale tileSize (Hero.position hero)

        ( xOff, yOff ) =
            ( windowSize.width // 2, windowSize.height // 2 )

        tolerance =
            tileSize * 4

        scroll =
            { up = viewport.y + curY <= tolerance
            , down = viewport.y + curY >= (windowSize.height * 4 // 5) - tolerance
            , left = viewport.x + curX <= tolerance
            , right = viewport.x + curX >= windowSize.width - tolerance
            }

        ( mapWidth, mapHeight ) =
            (Level.size (Maps.currentLevel maps))

        newX =
            if prevX /= curX && (scroll.left || scroll.right) then
                clamp (windowSize.width - mapWidth * tileSize) 0 (xOff - curX)
            else
                viewport.x

        newY =
            if prevY /= curY && (scroll.up || scroll.down) then
                clamp (windowSize.height * 4 // 5 - mapHeight * tileSize) 0 (yOff - curY)
            else
                viewport.y
    in
        { model | viewport = { x = newX, y = newY } }


donDefaultGarb : ItemFactory -> Hero -> ( Hero, ItemFactory )
donDefaultGarb itemFactory hero =
    let
        equipmentToMake =
            [ ( Equipment.WeaponSlot, Item.Data.ItemTypeWeapon Dagger )
            , ( Equipment.ArmourSlot, Item.Data.ItemTypeArmour ScaleMail )
            , ( Equipment.ShieldSlot, Item.Data.ItemTypeShield LargeIronShield )
            , ( Equipment.HelmetSlot, Item.Data.ItemTypeHelmet LeatherHelmet )
            , ( Equipment.GauntletsSlot, Item.Data.ItemTypeGauntlets NormalGauntlets )
            , ( Equipment.BeltSlot, Item.Data.ItemTypeBelt ThreeSlotBelt )
            , ( Equipment.PurseSlot, Item.Data.ItemTypePurse )
            , ( Equipment.PackSlot, Item.Data.ItemTypePack MediumPack )
            ]

        makeEquipment ( slot, itemType ) ( accEquipment, itemFactory ) =
            let
                ( item, itemFactory_ ) =
                    ItemFactory.make itemType itemFactory
            in
                ( ( slot, item ) :: accEquipment, itemFactory_ )

        ( defaultEquipment, factoryAfterProduction ) =
            List.foldl makeEquipment ( [], itemFactory ) equipmentToMake

        equippingHero =
            Lib.foldResult (\item -> Hero.equip item) (Ok hero) defaultEquipment
    in
        case equippingHero of
            Result.Ok heroEquipped ->
                ( heroEquipped, factoryAfterProduction )

            err ->
                let
                    _ =
                        Debug.log "Game.donDefaultGarb" (toString err)
                in
                    ( hero, itemFactory )



----------
-- View --
----------


view : Model -> Html Msg
view model =
    case model.currentScreen of
        MapScreen ->
            viewMap model

        BuildingScreen building ->
            case Building.buildingType building of
                Building.Shop shopType ->
                    Html.map InventoryMsg (Inventory.view model.inventory)

                _ ->
                    viewBuilding building

        InventoryScreen ->
            Html.map InventoryMsg (Inventory.view model.inventory)


viewMonsters : Model -> Html Msg
viewMonsters model =
    let
        monsters =
            model.maps
                |> Maps.currentLevel
                |> .monsters

        monsterHtml monster =
            Monster.view monster
    in
        div [] (List.map monsterHtml monsters)


viewMap : Model -> Html Msg
viewMap ({ windowSize, viewport } as model) =
    let
        title =
            h1 [] [ text ("Welcome to Castle of the Winds: " ++ model.name) ]

        px x =
            (toString x) ++ "px"

        adjustViewport html =
            div
                [ style
                    [ ( "position", "relative" )
                    , ( "overflow", "hidden" )
                    , ( "width", px windowSize.width )
                    , ( "height", px (windowSize.height * 4 // 5) )
                    ]
                ]
                [ div
                    [ style
                        [ ( "position", "relative" )
                        , ( "top", px viewport.y )
                        , ( "left", px viewport.x )
                        ]
                    ]
                    html
                ]

        viewSize =
            ( windowSize.width // 32, windowSize.height // 32 )

        viewStart =
            ( abs <| viewport.x // 32, abs <| viewport.y // 32 )
    in
        div []
            [ viewMenu
            , viewQuickMenu
            , adjustViewport
                [ Maps.view ( viewStart, viewSize ) ClickTile model.maps
                , Hero.view model.hero
                , viewMonsters model
                ]
            , viewStatus model
            ]


viewStatus : Model -> Html Msg
viewStatus model =
    div []
        [ div [ class "ui padded grid" ]
            [ div [ style [ ( "overflow", "auto" ), ( "height", "100px" ) ], class "ui twelve wide column" ]
                [ viewMessages model ]
            , div [ class "ui four wide column" ]
                [ Hero.viewStats model.hero ]
            ]
        ]


viewMessages : Model -> Html Msg
viewMessages model =
    let
        msg txt =
            div [] [ text txt ]
    in
        div [] (List.map msg model.messages)


viewMenu : Html Msg
viewMenu =
    div [ class "ui buttons" ]
        (List.map simpleBtn
            [ "File"
            , "Character!"
            , "Inventory!"
            , "Map!"
            , "Spells"
            , "Activate"
            , "Verbs"
            , "Options"
            , "Window"
            , "Help"
            ]
        )


viewQuickMenu : Html Msg
viewQuickMenu =
    div []
        (List.map simpleBtn
            [ "Get"
            , "Free Hand"
            , "Search"
            , "Disarm"
            , "Rest"
            , "Save"
            ]
        )


viewHUD : Model -> Html Msg
viewHUD model =
    div [] [ text "messages" ]


viewBuilding : Building -> Html Msg
viewBuilding building =
    div [] [ h1 [] [ text "TODO: Get the internal view of the building" ] ]


subscription : Model -> Sub Msg
subscription model =
    Sub.batch
        [ Window.resizes (\x -> WindowSize x)
        , Sub.map InventoryMsg (Inventory.subscription model.inventory)
        , Sub.map Keyboard (Keyboard.subscription)
        ]



--------------
-- Commands --
--------------


initialWindowSizeCmd : Cmd Msg
initialWindowSizeCmd =
    Task.perform (\x -> WindowSize x) Window.size



--------
-- UI --
--------


simpleBtn : String -> Html Msg
simpleBtn txt =
    div [ class "ui button" ] [ text txt ]
