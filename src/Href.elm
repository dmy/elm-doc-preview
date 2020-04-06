module Href exposing (toModule, toProject, toVersion)

{-|

@docs toModule, toProject, toVersion

-}

import Elm.Version as V
import Url.Builder as Url



-- HREFS


{-| -}
toProject : String -> String -> String
toProject author project =
    Url.absolute [ "packages", author, project, "" ] []


{-| -}
toVersion : String -> String -> Maybe V.Version -> Maybe String -> String
toVersion author project version fragment =
    Url.custom Url.Absolute [ "packages", author, project, vsnToString version, "" ] [] fragment


{-| -}
toModule : String -> String -> Maybe V.Version -> String -> Maybe String -> String
toModule author project version moduleName fragment =
    Url.custom Url.Absolute [ "packages", author, project, vsnToString version, String.replace "." "-" moduleName ] [] fragment



-- HELPERS


vsnToString : Maybe V.Version -> String
vsnToString maybeVersion =
    case maybeVersion of
        Nothing ->
            "latest"

        Just version ->
            V.toString version
