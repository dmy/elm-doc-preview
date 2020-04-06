module Page.Docs exposing
    ( Focus(..), Model, Msg
    , init, update, view
    , toTitle
    , updateReadme, updateDocs, updateManifest
    )

{-|

@docs Focus, Model, Msg
@docs init, update, view
@docs toTitle
@docs updateReadme, updateDocs, updateManifest

-}

import Browser.Dom as Dom
import DateFormat
import Elm.Constraint as Constraint exposing (Constraint)
import Elm.Docs as Docs
import Elm.License as License
import Elm.Package as Package
import Elm.Project as Project exposing (Project)
import Elm.Version as Version exposing (Version)
import Href
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (..)
import Http
import Page.Docs.Block as Block
import Page.Problem as Problem
import Release
import Session exposing (Docs(..))
import Skeleton
import Task
import Time
import Url.Builder as Url
import Utils.Error
import Utils.Markdown as Markdown
import Utils.OneOrMore exposing (OneOrMore)
import Utils.Spinner



-- MODEL


{-| -}
type alias Model =
    { session : Session.Data
    , author : String
    , project : String
    , version : Maybe Version
    , focus : Focus
    , query : String
    , latest : Status Version
    , readme : Status String
    , docs : Status Docs
    , manifest : Status Project
    }


{-| -}
type Focus
    = Readme (Maybe String)
    | Module String (Maybe String)


type Status a
    = Failure
    | Loading
    | Success a



-- INIT


{-| -}
init : Session.Data -> String -> String -> Maybe Version -> Focus -> ( Model, Cmd Msg )
init session author project version focus =
    case Session.getReleases session author project of
        Just releases ->
            let
                latest =
                    Release.getLatest releases
            in
            getInfo latest <|
                Model session author project version focus "" (Success latest) Loading Loading Loading

        Nothing ->
            ( Model session author project version focus "" Loading Loading Loading Loading
            , Session.fetchReleases GotReleases author project
            )


getInfo : Version -> Model -> ( Model, Cmd Msg )
getInfo latest model =
    let
        author =
            model.author

        project =
            model.project

        version =
            Maybe.withDefault latest model.version

        maybeInfo =
            Maybe.map3 (\readme docs manifest -> ( readme, docs, manifest ))
                (Session.getReadme model.session author project version)
                (Session.getDocs model.session author project version)
                (Session.getManifest model.session author project version)
    in
    case maybeInfo of
        Nothing ->
            ( model
            , Cmd.batch
                [ Session.fetchReadme (GotReadme version) author project version
                , Session.fetchDocs (GotDocs version) author project version
                , Session.fetchManifest (GotManifest version) author project version
                ]
            )

        Just ( readme, docs, manifest ) ->
            ( { model
                | readme = Success readme
                , docs = Success docs
                , manifest = Success manifest
              }
            , scrollIfNeeded model.focus
            )


scrollIfNeeded : Focus -> Cmd Msg
scrollIfNeeded focus =
    let
        scrollToTag tag =
            Dom.getElement tag
                |> Task.andThen (\info -> Dom.setViewport 0 info.element.y)
                |> Task.attempt ScrollAttempted
    in
    case focus of
        Readme (Just tag) ->
            scrollToTag tag

        Module _ (Just tag) ->
            scrollToTag tag

        _ ->
            Cmd.none



-- UPDATE


{-| -}
type Msg
    = QueryChanged String
    | ScrollAttempted (Result Dom.Error ())
    | GotReleases (Result Http.Error (OneOrMore Release.Release))
    | GotReadme Version (Result Http.Error String)
    | GotDocs Version (Result Http.Error Docs)
    | GotManifest Version (Result Http.Error Project)


{-| -}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        QueryChanged query ->
            ( { model | query = query }
            , Cmd.none
            )

        ScrollAttempted _ ->
            ( model
            , Cmd.none
            )

        GotReleases result ->
            case result of
                Err _ ->
                    ( { model
                        | latest = Failure
                        , readme = Failure
                        , docs = Failure
                      }
                    , Cmd.none
                    )

                Ok releases ->
                    let
                        latest =
                            Release.getLatest releases
                    in
                    getInfo latest
                        { model
                            | latest = Success latest
                            , session = Session.addReleases model.author model.project releases model.session
                            , version =
                                if model.version == Nothing then
                                    Just latest

                                else
                                    model.version
                        }

        GotReadme version result ->
            case result of
                Err _ ->
                    ( { model | readme = Failure }
                    , Cmd.none
                    )

                Ok readme ->
                    ( { model
                        | readme = Success readme
                        , session = Session.addReadme model.author model.project version readme model.session
                      }
                    , Cmd.none
                    )

        GotDocs version result ->
            case result of
                Err _ ->
                    ( { model | docs = Failure }
                    , Cmd.none
                    )

                Ok docs ->
                    ( { model
                        | docs = Success docs
                        , session = Session.addDocs model.author model.project version docs model.session
                      }
                    , scrollIfNeeded model.focus
                    )

        GotManifest version result ->
            case result of
                Err err ->
                    ( { model | manifest = Failure }
                    , Cmd.none
                    )

                Ok manifest ->
                    ( { model
                        | manifest = Success manifest
                        , session = Session.addManifest model.author model.project version manifest model.session
                      }
                    , Cmd.none
                    )



-- EXTERNAL UPDATES


{-| -}
updateReadme : String -> String -> Version -> String -> Model -> Model
updateReadme author project version readme model =
    let
        newSession =
            Session.addReadme author project version readme model.session
    in
    if author == model.author && project == model.project && Just version == model.version then
        { model | session = newSession, readme = Success readme }

    else
        { model | session = newSession }


{-| -}
updateDocs : String -> String -> Version -> Docs -> Model -> Model
updateDocs author project version docs model =
    let
        newSession =
            Session.addDocs author project version docs model.session
    in
    if author == model.author && project == model.project && Just version == model.version then
        { model | session = newSession, docs = Success docs }

    else
        { model | session = newSession }


{-| -}
updateManifest : String -> String -> Version -> Project -> Model -> Model
updateManifest author project version manifest model =
    let
        newSession =
            Session.addManifest author project version manifest model.session
    in
    if author == model.author && project == model.project && Just version == model.version then
        { model | session = newSession, manifest = Success manifest }

    else
        { model | session = newSession }



-- VIEW


{-| -}
view : Model -> Skeleton.Details Msg
view model =
    { title = toTitle model
    , header = toHeader model
    , warning = toWarning model
    , attrs = []
    , kids =
        [ viewContent model
        , viewSidebar model
        ]
    }



-- TITLE


{-| -}
toTitle : Model -> String
toTitle model =
    case model.focus of
        Readme _ ->
            toGenericTitle model

        Module name _ ->
            name ++ " - " ++ toGenericTitle model


toGenericTitle : Model -> String
toGenericTitle model =
    case getVersion model of
        Just version ->
            model.project ++ " " ++ Version.toString version

        Nothing ->
            model.project


getVersion : Model -> Maybe Version
getVersion model =
    case model.version of
        Just version ->
            model.version

        Nothing ->
            case model.latest of
                Success version ->
                    Just version

                Loading ->
                    Nothing

                Failure ->
                    Nothing



-- TO HEADER


toHeader : Model -> List Skeleton.Segment
toHeader model =
    [ Skeleton.authorSegment model.author
    , Skeleton.projectSegment model.author model.project
    , Skeleton.versionSegment model.author model.project (getVersion model)
    ]



-- WARNING


toWarning : Model -> Skeleton.Warning
toWarning model =
    case model.version of
        Nothing ->
            Skeleton.NoProblems

        Just version ->
            case model.latest of
                Success latest ->
                    if version == latest then
                        Skeleton.NoProblems

                    else
                        Skeleton.NewerVersion (toNewerUrl model) latest

                Loading ->
                    Skeleton.NoProblems

                Failure ->
                    Skeleton.NoProblems


toNewerUrl : Model -> String
toNewerUrl model =
    case model.focus of
        Readme tag ->
            Href.toVersion model.author model.project Nothing tag

        Module name tag ->
            Href.toModule model.author model.project Nothing name tag



-- VIEW CONTENT


viewContent : Model -> Html msg
viewContent model =
    case model.focus of
        Readme _ ->
            case model.docs of
                Success (Error error) ->
                    lazy Utils.Error.view error

                _ ->
                    lazy viewReadme model.readme

        Module name tag ->
            lazy5 viewModule model.author model.project model.version name model.docs



-- VIEW README


viewReadme : Status String -> Html msg
viewReadme status =
    case status of
        Success readme ->
            div [ class "block-list" ] [ Markdown.block readme ]

        Loading ->
            Utils.Spinner.view

        -- TODO
        Failure ->
            div
                (class "block-list" :: Problem.styles)
                (Problem.offline "README.md")



-- VIEW MODULE


viewModule : String -> String -> Maybe Version -> String -> Status Docs -> Html msg
viewModule author project version name status =
    case status of
        Success (Modules allDocs) ->
            case findModule name allDocs of
                Just docs ->
                    let
                        header =
                            h1 [ class "block-list-title" ] [ text name ]

                        info =
                            Block.makeInfo author project version name allDocs

                        blocks =
                            List.map (Block.view info) (Docs.toBlocks docs)
                    in
                    div [ class "block-list" ] (header :: blocks)

                Nothing ->
                    div
                        (class "block-list" :: Problem.styles)
                        (Problem.missingModule author project version name)

        Success (Error error) ->
            lazy Utils.Error.view error

        Loading ->
            div [ class "block-list" ]
                [ h1 [ class "block-list-title" ] [ text name ] -- TODO better loading
                , Utils.Spinner.view
                ]

        Failure ->
            div
                (class "block-list" :: Problem.styles)
                (Problem.offline "docs.json")


findModule : String -> List Docs.Module -> Maybe Docs.Module
findModule name docsList =
    case docsList of
        [] ->
            Nothing

        docs :: otherDocs ->
            if docs.name == name then
                Just docs

            else
                findModule name otherDocs



-- VIEW SIDEBAR


viewSidebar : Model -> Html Msg
viewSidebar model =
    div
        [ class "pkg-nav"
        ]
        [ lazy4 viewReadmeLink model.author model.project model.version model.focus
        , br [] []
        , lazy4 viewBrowseSourceLink model.author model.project model.version model.latest
        , h2 [ style "margin-bottom" "0" ] [ text "Modules" ]
        , input
            [ placeholder "Search"
            , value model.query
            , onInput QueryChanged
            ]
            []
        , viewSidebarModules model
        , viewInstall model.manifest model.author model.project
        , viewLicense model.manifest
        , viewDependencies model.manifest
        ]


viewSidebarModules : Model -> Html msg
viewSidebarModules model =
    case model.docs of
        Failure ->
            text ""

        -- TODO
        Loading ->
            text ""

        Success (Modules modules) ->
            if String.isEmpty model.query then
                let
                    viewEntry docs =
                        li [] [ viewModuleLink model docs.name ]
                in
                ul [] (List.map viewEntry modules)

            else
                let
                    query =
                        model.query |> String.toLower |> String.trim
                in
                ul [] (List.filterMap (viewSearchItem model query) modules)

        Success (Error _) ->
            text ""


viewSearchItem : Model -> String -> Docs.Module -> Maybe (Html msg)
viewSearchItem model query docs =
    let
        toItem ownerName valueName =
            viewValueItem model docs.name ownerName valueName

        matches =
            List.filterMap (isMatch query toItem) docs.binops
                ++ List.concatMap (isUnionMatch query toItem) docs.unions
                ++ List.filterMap (isMatch query toItem) docs.aliases
                ++ List.filterMap (isMatch query toItem) docs.values
    in
    if List.isEmpty matches && not (String.contains query docs.name) then
        Nothing

    else
        Just <|
            li
                [ class "pkg-nav-search-chunk"
                ]
                [ viewModuleLink model docs.name
                , ul [] matches
                ]


isMatch : String -> (String -> String -> b) -> { r | name : String } -> Maybe b
isMatch query toResult { name } =
    if String.contains query (String.toLower name) then
        Just (toResult name name)

    else
        Nothing


isUnionMatch : String -> (String -> String -> a) -> Docs.Union -> List a
isUnionMatch query toResult { name, tags } =
    let
        tagMatches =
            List.filterMap (isTagMatch query toResult name) tags
    in
    if String.contains query (String.toLower name) then
        toResult name name :: tagMatches

    else
        tagMatches


isTagMatch : String -> (String -> String -> a) -> String -> ( String, details ) -> Maybe a
isTagMatch query toResult tipeName ( tagName, _ ) =
    if String.contains query (String.toLower tagName) then
        Just (toResult tipeName tagName)

    else
        Nothing



-- VIEW "README" LINK


viewReadmeLink : String -> String -> Maybe Version -> Focus -> Html msg
viewReadmeLink author project version focus =
    navLink "README" (Href.toVersion author project version Nothing) <|
        case focus of
            Readme _ ->
                True

            Module _ _ ->
                False



-- VIEW "SOURCE" LINK


viewBrowseSourceLink : String -> String -> Maybe Version -> Status Version -> Html msg
viewBrowseSourceLink author project maybeVersion latest =
    case maybeVersion of
        Just version ->
            viewBrowseSourceLinkHelp author project version

        Nothing ->
            case latest of
                Success version ->
                    viewBrowseSourceLinkHelp author project version

                Loading ->
                    text "Source"

                Failure ->
                    text "Source"


viewBrowseSourceLinkHelp : String -> String -> Version -> Html msg
viewBrowseSourceLinkHelp author project version =
    let
        url =
            Url.absolute
                [ "source", author, project, Version.toString version ]
                []
    in
    a [ class "pkg-nav-module", href url ] [ text "Source" ]



-- VIEW "MODULE" LINK


viewModuleLink : Model -> String -> Html msg
viewModuleLink model name =
    let
        url =
            Href.toModule model.author model.project model.version name Nothing
    in
    navLink name url <|
        case model.focus of
            Readme _ ->
                False

            Module selectedName _ ->
                selectedName == name


viewValueItem : Model -> String -> String -> String -> Html msg
viewValueItem { author, project, version } moduleName ownerName valueName =
    let
        url =
            Href.toModule author project version moduleName (Just ownerName)
    in
    li [ class "pkg-nav-value" ] [ navLink valueName url False ]



-- LINK HELPERS


navLink : String -> String -> Bool -> Html msg
navLink name url isBold =
    let
        attributes =
            if isBold then
                [ class "pkg-nav-module"
                , style "font-weight" "bold"
                , style "text-decoration" "underline"
                ]

            else
                [ class "pkg-nav-module"
                ]
    in
    a (href url :: attributes) [ text name ]



-- VIEW INSTALL


viewInstall : Status Project -> String -> String -> Html msg
viewInstall manifest author project =
    case manifest of
        Success (Project.Package info) ->
            let
                install =
                    "elm install " ++ author ++ "/" ++ project
            in
            div []
                [ h2 [] [ text "Install" ]
                , pre
                    [ class "copy-to-clipboard"
                    , attribute "data-clipboard-text" install
                    ]
                    [ text install
                    ]
                ]

        _ ->
            text ""



-- VIEW LICENSE


viewLicense : Status Project -> Html msg
viewLicense manifest =
    case manifest of
        Success (Project.Package info) ->
            let
                licenseUrl =
                    Url.absolute
                        [ "source"
                        , Package.toString info.name
                        , Version.toString info.version
                        , "LICENSE"
                        ]
                        []
            in
            div []
                [ h2 [] [ text "License" ]
                , div []
                    [ a [ href licenseUrl ]
                        [ nowrap []
                            [ License.toString info.license ]
                        ]
                    ]
                ]

        _ ->
            text ""


nowrap : List (Attribute msg) -> List String -> Html msg
nowrap attrs children =
    span
        (style "white-space" "nowrap" :: attrs)
        (List.map text children)



-- VIEW DEPENDENCIES


viewDependencies : Status Project -> Html msg
viewDependencies manifest =
    case manifest of
        Success (Project.Package info) ->
            div []
                (h2 [] [ text "Dependencies" ]
                    :: viewElmVersion Constraint.toString info.elm
                    :: List.map viewDepConstraint info.deps
                )

        Success (Project.Application info) ->
            div []
                (h2 [] [ text "Dependencies" ]
                    :: viewElmVersion Version.toString info.elm
                    :: List.map viewDepVersion info.depsDirect
                )

        _ ->
            text ""


viewElmVersion : (version -> String) -> version -> Html msg
viewElmVersion versionToString version =
    div [ style "white-space" "nowrap" ]
        [ text ("elm " ++ versionToString version)
        ]


viewDepConstraint : ( Package.Name, Constraint ) -> Html msg
viewDepConstraint ( name, constraint ) =
    div [ style "white-space" "nowrap" ]
        [ a
            [ href <|
                Url.absolute [ "packages", Package.toString name, "latest" ] []
            ]
            [ text (Package.toString name) ]
        , text (" " ++ Constraint.toString constraint)
        ]


viewDepVersion : ( Package.Name, Version ) -> Html msg
viewDepVersion ( name, version ) =
    div [ style "white-space" "nowrap" ]
        [ a
            [ href <|
                Url.absolute
                    [ "packages"
                    , Package.toString name
                    , Version.toString version
                    ]
                    []
            ]
            [ text (Package.toString name ++ " " ++ Version.toString version)
            ]
        ]
