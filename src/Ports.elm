port module Ports exposing (Docs, Manifest, Readme, onDocs, onManifest, onReadme)

import Json.Encode as Encode


type alias Readme =
    { author : String
    , project : String
    , version : String
    , readme : String
    }


type alias Docs =
    { author : String
    , project : String
    , version : String
    , docs : Encode.Value
    }


type alias Manifest =
    { author : String
    , project : String
    , version : String
    , timestamp : Int
    , manifest : Encode.Value
    }


port onReadme : (Readme -> msg) -> Sub msg


port onDocs : (Docs -> msg) -> Sub msg


port onManifest : (Manifest -> msg) -> Sub msg
