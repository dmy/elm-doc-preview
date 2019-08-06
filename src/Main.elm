module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Dict
import Elm.Version as V
import Html
import Page.Diff as Diff
import Page.Package as Package
import Page.Problem as Problem
import Page.Search as Search
import Session
import Skeleton
import Url
import Url.Parser as Parser exposing ((</>), Parser, custom, fragment, map, oneOf, s, top)



-- MAIN


main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }



-- MODEL


type alias Model =
    { key : Nav.Key
    , page : Page
    }


type Page
    = NotFound Session.Data
    | Search Search.Model
    | Package Package.Model
    | Diff Diff.Model



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Model -> Browser.Document Msg
view model =
    case model.page of
        NotFound _ ->
            Skeleton.view never
                { title = "Not Found"
                , header = []
                , warning = Skeleton.NoProblems
                , attrs = Problem.styles
                , kids = Problem.notFound
                }

        Search search ->
            Skeleton.view SearchMsg (Search.view search)

        Package pkg ->
            Skeleton.view PackageMsg (Package.view pkg)

        Diff diff ->
            Skeleton.view never (Diff.view diff)



-- INIT


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    stepUrl url
        { key = key
        , page = NotFound Session.empty
        }



-- UPDATE


type Msg
    = NoOp
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | SearchMsg Search.Msg
    | DiffMsg Diff.Msg
    | PackageMsg Package.Msg


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    case message of
        NoOp ->
            ( model, Cmd.none )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , if String.startsWith "/source/" url.path then
                        Nav.load (Url.toString url)

                      else
                        Nav.pushUrl model.key (Url.toString url)
                    )

                Browser.External href ->
                    ( model
                    , Nav.load href
                    )

        UrlChanged url ->
            stepUrl url model

        SearchMsg msg ->
            case model.page of
                Search search ->
                    stepSearch model (Search.update msg search)

                _ ->
                    ( model, Cmd.none )

        DiffMsg msg ->
            case model.page of
                Diff diff ->
                    stepDiff model (Diff.update msg diff)

                _ ->
                    ( model, Cmd.none )

        PackageMsg msg ->
            case model.page of
                Package pkg ->
                    stepPackage model (Package.update msg pkg)

                _ ->
                    ( model, Cmd.none )


stepSearch : Model -> ( Search.Model, Cmd Search.Msg ) -> ( Model, Cmd Msg )
stepSearch model ( search, cmds ) =
    ( { model | page = Search search }
    , Cmd.map SearchMsg cmds
    )


stepPackage : Model -> ( Package.Model, Cmd Package.Msg ) -> ( Model, Cmd Msg )
stepPackage model ( pkg, cmds ) =
    ( { model | page = Package pkg }
    , Cmd.map PackageMsg cmds
    )


stepDiff : Model -> ( Diff.Model, Cmd Diff.Msg ) -> ( Model, Cmd Msg )
stepDiff model ( diff, cmds ) =
    ( { model | page = Diff diff }
    , Cmd.map DiffMsg cmds
    )



-- EXIT


exit : Model -> Session.Data
exit model =
    case model.page of
        NotFound session ->
            session

        Search m ->
            m.session

        Package m ->
            m.session

        Diff m ->
            m.session



-- ROUTER


stepUrl : Url.Url -> Model -> ( Model, Cmd Msg )
stepUrl url model =
    let
        session =
            exit model

        parser =
            oneOf
                [ route top
                    (stepSearch model (Search.init session))
                , route (s "packages" </> author_ </> project_)
                    (\author project ->
                        stepDiff model (Diff.init session author project)
                    )
                , route (s "packages" </> author_ </> project_ </> version_ </> focus_)
                    (\author project version focus ->
                        stepPackage model (Package.init session author project version focus)
                    )
                ]
    in
    case Parser.parse parser url of
        Just answer ->
            answer

        Nothing ->
            ( { model | page = NotFound session }
            , Cmd.none
            )


route : Parser a b -> a -> Parser (b -> c) c
route parser handler =
    Parser.map handler parser


author_ : Parser (String -> a) a
author_ =
    custom "AUTHOR" Just


project_ : Parser (String -> a) a
project_ =
    custom "PROJECT" Just


version_ : Parser (Maybe V.Version -> a) a
version_ =
    custom "VERSION" <|
        \string ->
            if string == "latest" then
                Just Nothing

            else
                Maybe.map Just (V.fromString string)


focus_ : Parser (Package.Focus -> a) a
focus_ =
    oneOf
        [ map Package.Readme top
        , map Package.Module (moduleName_ </> fragment identity)
        ]


moduleName_ : Parser (String -> a) a
moduleName_ =
    custom "MODULE" (Just << String.replace "-" ".")
