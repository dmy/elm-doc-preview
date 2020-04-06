module Release exposing (Release, decoder, getLatest)

{-|

@docs Release, decoder, getLatest

-}

import Elm.Version as V
import Json.Decode as D
import Time
import Utils.OneOrMore exposing (OneOrMore(..))



-- RELEASE


{-| -}
type alias Release =
    { version : V.Version
    , time : Time.Posix
    }



-- GET LATEST VERSION


{-| -}
getLatest : OneOrMore Release -> V.Version
getLatest (OneOrMore r rs) =
    getLatestVersionHelp rs r


getLatestVersionHelp : List Release -> Release -> V.Version
getLatestVersionHelp releases maxRelease =
    case releases of
        [] ->
            maxRelease.version

        release :: otherReleases ->
            getLatestVersionHelp otherReleases <|
                if V.compare release.version maxRelease.version == GT then
                    release

                else
                    maxRelease



-- JSON


{-| -}
decoder : D.Decoder (OneOrMore Release)
decoder =
    D.keyValuePairs (D.map (\i -> Time.millisToPosix (i * 1000)) D.int)
        |> D.andThen (decoderHelp [])


decoderHelp : List Release -> List ( String, Time.Posix ) -> D.Decoder (OneOrMore Release)
decoderHelp revReleases pairs =
    case pairs of
        [] ->
            case List.reverse revReleases of
                [] ->
                    D.fail "Expecting at least one release!"

                r :: rs ->
                    D.succeed (OneOrMore r rs)

        ( str, time ) :: otherPairs ->
            case V.fromString str of
                Nothing ->
                    D.fail <| "Field `" ++ str ++ "` must be a valid version, like 3.1.4"

                Just vsn ->
                    decoderHelp
                        (Release vsn time :: revReleases)
                        otherPairs
