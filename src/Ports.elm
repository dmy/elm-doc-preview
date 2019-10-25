port module Ports exposing
    ( Docs, Manifest, Readme
    , onReadme, onDocs, onManifest
    , locationHrefRequested
    )

{-|

@docs Docs, Manifest, Readme
@docs onReadme, onDocs, onManifest
@docs locationHrefRequested

-}

import Json.Encode as Encode


{-| -}
type alias Readme =
    { author : String
    , project : String
    , version : String
    , readme : String
    }


{-| -}
type alias Docs =
    { author : String
    , project : String
    , version : String
    , docs : Encode.Value
    }


{-| -}
type alias Manifest =
    { author : String
    , project : String
    , version : String
    , timestamp : Int
    , manifest : Encode.Value
    }


{-| -}
port onReadme : (Readme -> msg) -> Sub msg


{-| -}
port onDocs : (Docs -> msg) -> Sub msg


{-| -}
port onManifest : (Manifest -> msg) -> Sub msg


{-| -}
port locationHrefRequested : (String -> msg) -> Sub msg
