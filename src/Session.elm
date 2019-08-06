module Session exposing
    ( Data
    , addDocs
    , addEntries
    , addManifest
    , addReadme
    , addReleases
    , empty
    , fetchDocs
    , fetchManifest
    , fetchReadme
    , fetchReleases
    , getDocs
    , getEntries
    , getManifest
    , getReadme
    , getReleases
    )

import Dict exposing (Dict)
import Elm.Docs as Docs
import Elm.Project as Project exposing (Project)
import Elm.Version as V
import Http
import Imf.DateTime
import Json.Decode as Decode
import Page.Search.Entry as Entry
import Parser
import Release exposing (Release)
import Time
import Url.Builder as Url
import Utils.OneOrMore exposing (OneOrMore(..))



-- SESSION DATA


type alias Data =
    { entries : Maybe (Dict String Entry.Entry)
    , releases : Dict.Dict String (OneOrMore Release.Release)
    , readmes : Dict.Dict String String
    , docs : Dict.Dict String (List Docs.Module)
    , manifests : Dict.Dict String ( Time.Posix, Project )
    }


empty : Data
empty =
    Data Nothing Dict.empty Dict.empty Dict.empty Dict.empty



-- ENTRIES


getEntries : Data -> Maybe (Dict String Entry.Entry)
getEntries data =
    data.entries


addEntries : Dict String Entry.Entry -> Data -> Data
addEntries entries data =
    { data | entries = Just entries }



-- RELEASES


toPkgKey : String -> String -> String
toPkgKey author project =
    author ++ "/" ++ project


getReleases : Data -> String -> String -> Maybe (OneOrMore Release)
getReleases data author project =
    Dict.get (toPkgKey author project) data.releases


addReleases : String -> String -> OneOrMore Release -> Data -> Data
addReleases author project releases data =
    let
        newReleases =
            Dict.insert (toPkgKey author project) releases data.releases
    in
    { data | releases = newReleases }


fetchReleases : (Result Http.Error (OneOrMore Release) -> msg) -> String -> String -> Cmd msg
fetchReleases toMsg author project =
    Http.get
        { url = Url.absolute [ "packages", author, project, "releases.json" ] []
        , expect = Http.expectJson toMsg Release.decoder
        }



-- README


toVsnKey : String -> String -> V.Version -> String
toVsnKey author project version =
    author ++ "/" ++ project ++ "@" ++ V.toString version


getReadme : Data -> String -> String -> V.Version -> Maybe String
getReadme data author project version =
    Dict.get (toVsnKey author project version) data.readmes


addReadme : String -> String -> V.Version -> String -> Data -> Data
addReadme author project version readme data =
    let
        newReadmes =
            Dict.insert (toVsnKey author project version) readme data.readmes
    in
    { data | readmes = newReadmes }


fetchReadme : (Result Http.Error String -> msg) -> String -> String -> V.Version -> Cmd msg
fetchReadme toMsg author project version =
    Http.get
        { url = Url.absolute [ "packages", author, project, V.toString version, "README.md" ] []
        , expect = Http.expectString toMsg
        }



-- DOCS


getDocs : Data -> String -> String -> V.Version -> Maybe (List Docs.Module)
getDocs data author project version =
    Dict.get (toVsnKey author project version) data.docs


addDocs : String -> String -> V.Version -> List Docs.Module -> Data -> Data
addDocs author project version docs data =
    let
        newDocs =
            Dict.insert (toVsnKey author project version) docs data.docs
    in
    { data | docs = newDocs }


fetchDocs : (Result Http.Error (List Docs.Module) -> msg) -> String -> String -> V.Version -> Cmd msg
fetchDocs toMsg author project version =
    Http.get
        { url = Url.absolute [ "packages", author, project, V.toString version, "docs.json" ] []
        , expect = Http.expectJson toMsg (Decode.list Docs.decoder)
        }



-- MANIFEST


getManifest : Data -> String -> String -> V.Version -> Maybe ( Time.Posix, Project )
getManifest data author project version =
    Dict.get (toVsnKey author project version) data.manifests


addManifest : String -> String -> V.Version -> ( Time.Posix, Project ) -> Data -> Data
addManifest author project version manifest data =
    let
        newManifests =
            Dict.insert (toVsnKey author project version) manifest data.manifests
    in
    { data | manifests = newManifests }


fetchManifest :
    (Result Http.Error ( Time.Posix, Project ) -> msg)
    -> String
    -> String
    -> V.Version
    -> Cmd msg
fetchManifest toMsg author project version =
    Http.get
        { url = Url.absolute [ "packages", author, project, V.toString version, "elm.json" ] []
        , expect = expectProject toMsg
        }


expectProject : (Result Http.Error ( Time.Posix, Project ) -> msg) -> Http.Expect msg
expectProject toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err (Http.BadUrl url)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ metadata body ->
                    Err (Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ metadata body ->
                    expectProjectHelp metadata body


expectProjectHelp : Http.Metadata -> String -> Result Http.Error ( Time.Posix, Project )
expectProjectHelp metadata body =
    let
        lastModified =
            Dict.get "last-modified" metadata.headers
                |> Result.fromMaybe
                    [ { row = 1
                      , col = 1
                      , problem = Parser.Expecting "last-modified header"
                      }
                    ]
                |> Result.andThen Imf.DateTime.toPosix
    in
    case ( lastModified, Decode.decodeString Project.decoder body ) of
        ( Ok time, Ok value ) ->
            Ok ( time, value )

        ( _, Err err ) ->
            Err (Http.BadBody (Decode.errorToString err))

        ( Err deadEnds, _ ) ->
            Err (Http.BadBody (Parser.deadEndsToString deadEnds))
