module SplashView exposing (view) -- where

{-| Shows the splash screen
@docs view
-}

import Html exposing (..)
import Html.Events exposing (onClick)
import Html.Attributes exposing (..)

{-| Shows the splash screen
  @doc view
-}
view: Html String
view =
  let 
    bgStyle = [("backgroundColor", "black")]
  in
  div [class "ui middle aligned center aligned grid fullscreen",
       style bgStyle] [
    div [class "ui one column"] [
      div [class "ui column"] [
        img [src "public/assets/landing_cotw1.jpg"] []
      ],

      div [class "ui column"] [
        img [src "public/assets/landing_cotw2.jpg"] []
      ],

      div [class "ui column"] [
        div [class "ui buttons"] [
          button [class "ui button primary", onClick "new"] [text "New Game"],
          button [class "ui button", onClick "load"] [text "Load Game"],
          button [class "ui button", onClick "overview"] [text "Overview"]
        ]
      ]
    ]
  ]