module Components.Diagram exposing (init, update, view)

import Basics exposing (max)
import Constants exposing (..)
import Html exposing (Html, div)
import Html.Attributes as Attr
import Html.Events.Extra.Mouse as Mouse
import Html.Events.Extra.Touch as Touch
import Html.Events.Extra.Wheel as Wheel
import List
import List.Extra exposing (getAt, scanl, unique)
import Models.Diagram exposing (..)
import Models.DiagramType exposing (DiagramType(..))
import Models.Item as Item exposing (Item, ItemType(..))
import Parser
import Result exposing (andThen)
import String
import Svg exposing (..)
import Svg.Attributes exposing (..)
import Svg.Events exposing (..)
import Svg.Lazy exposing (..)
import Utils
import Views.Diagram.BusinessModelCanvas as BusinessModelCanvas
import Views.Diagram.FourLs as FourLs
import Views.Diagram.Kpt as Kpt
import Views.Diagram.Markdown as Markdown
import Views.Diagram.MindMap as MindMap
import Views.Diagram.OpportunityCanvas as OpportunityCanvas
import Views.Diagram.StartStopContinue as StartStopContinue
import Views.Diagram.UserPersona as UserPersona
import Views.Diagram.UserStoryMap as UserStoryMap
import Views.Empty as Empty
import Views.Icon as Icon
import Views.MiniMap as MiniMap


init : Settings -> Model
init settings =
    { items = []
    , hierarchy = 0
    , width = 0
    , height = 0
    , svg =
        { width = 0
        , height = 0
        , scale = 1.0
        }
    , countByHierarchy = []
    , countByTasks = []
    , moveStart = False
    , x = 0
    , y = 20
    , moveX = 0
    , moveY = 0
    , fullscreen = False
    , showZoomControl = True
    , touchDistance = Nothing
    , settings = settings
    , error = Nothing
    , diagramType = UserStoryMap
    , labels = []
    , text = Nothing
    , showMiniMap = False
    , matchParent = False
    }


getItemType : String -> Int -> ItemType
getItemType text indent =
    if text |> String.trim |> String.startsWith "#" then
        Comments

    else
        case indent of
            0 ->
                Activities

            1 ->
                Tasks

            _ ->
                Stories (indent - 1)


loadText : DiagramType -> Int -> Int -> String -> Result String ( List Int, List Item )
loadText diagramType lineNo indent input =
    let
        splited =
            case diagramType of
                MindMap ->
                    Parser.parseLinesIgnoreError indent input

                _ ->
                    Parser.parseLines indent input
    in
    case splited of
        Ok ( x :: xs, xxs ) ->
            loadText diagramType (lineNo + 1) (indent + 1) (String.join "\n" xs)
                |> Result.andThen
                    (\( indents, items ) ->
                        loadText diagramType
                            (lineNo + List.length (x :: xs))
                            indent
                            (String.join "\n" xxs)
                            |> Result.andThen
                                (\( indents2, tailItems ) ->
                                    Ok
                                        ( indent :: indents ++ indents2
                                        , { lineNo = lineNo
                                          , text = x
                                          , itemType = getItemType x indent
                                          , children = Item.fromItems items
                                          }
                                            :: tailItems
                                            |> List.filter (\item -> item.itemType /= Comments)
                                        )
                                )
                    )

        Ok _ ->
            Ok ( [ indent ], [] )

        Err err ->
            Err err


load : DiagramType -> String -> Result String ( Int, List Item )
load diagramType t =
    case t of
        "" ->
            Ok ( 0, [] )

        _ ->
            let
                result =
                    loadText diagramType 0 0 t
            in
            case result of
                Ok ( i, loadedItems ) ->
                    Ok
                        ( i
                            |> List.maximum
                            |> Maybe.map (\x -> x - 1)
                            |> Maybe.withDefault 0
                        , loadedItems
                        )

                Err text ->
                    Err text


countUpToHierarchy : Int -> List Item -> List Int
countUpToHierarchy hierarchy items =
    let
        countUp : List Item -> List (List Int)
        countUp countItems =
            -- Do not count activity, task and comment items.
            [ countItems
                |> List.filter (\x -> x.itemType /= Tasks && x.itemType /= Activities)
                |> List.length
            ]
                :: (countItems
                        |> List.map
                            (\it ->
                                let
                                    results =
                                        countUp (Item.unwrapChildren it.children)
                                            |> transpose
                                in
                                if List.length results > hierarchy then
                                    List.map
                                        (\it2 ->
                                            List.maximum it2 |> Maybe.withDefault 0
                                        )
                                        results

                                else
                                    results
                                        |> List.concat
                                        |> List.filter (\x -> x /= 0)
                            )
                   )
    in
    1
        :: 1
        :: (countUp items
                |> transpose
                |> List.map
                    (\it ->
                        List.maximum it |> Maybe.withDefault 0
                    )
           )


transpose ll =
    case ll of
        [] ->
            []

        [] :: xss ->
            transpose xss

        (x :: xs) :: xss ->
            let
                heads =
                    List.filterMap List.head xss
                        |> unique

                tails =
                    List.filterMap List.tail xss
                        |> unique
            in
            (x :: heads) :: transpose (xs :: tails)


zoomControl : Bool -> Float -> Html Msg
zoomControl isFullscreen scale =
    let
        s =
            if 1.0 - scale > 0 then
                round ((1.0 + (1.0 - scale)) * 100.0)

            else if 1.0 - scale < 0 then
                round ((1.0 + (1.0 - scale)) * 100.0)

            else
                100
    in
    div
        [ id "zoom-control"
        , Attr.style "position" "absolute"
        , Attr.style "align-items" "center"
        , Attr.style "right" "35px"
        , Attr.style "top" "5px"
        , Attr.style "display" "flex"
        , Attr.style "width" "130px"
        , Attr.style "justify-content" "space-between"
        ]
        [ div
            [ Attr.style "width" "24px"
            , Attr.style "height" "24px"
            , Attr.style "cursor" "pointer"
            , onClick ZoomOut
            ]
            [ Icon.remove 24
            ]
        , div
            [ Attr.style "font-size" "0.7rem"
            , Attr.style "color" "#8C9FAE"
            , Attr.style "cursor" "pointer"
            , Attr.style "font-weight" "600"
            , class "svg-text"
            ]
            [ text (String.fromInt s ++ "%")
            ]
        , div
            [ Attr.style "width" "24px"
            , Attr.style "height" "24px"
            , Attr.style "cursor" "pointer"
            , onClick ZoomIn
            ]
            [ Icon.add 24
            ]
        , div
            [ Attr.style "width" "24px"
            , Attr.style "height" "24px"
            , Attr.style "cursor" "pointer"
            , onClick ToggleFullscreen
            ]
            [ if isFullscreen then
                Icon.fullscreenExit 24

              else
                Icon.fullscreen 24
            ]
        ]



-- View


view : Model -> Html Msg
view model =
    div
        [ Attr.id "usm-area"
        , Attr.style "position" "relative"
        , if model.moveStart then
            Attr.style "cursor" "move"

          else
            Attr.style "cursor" "auto"
        ]
        [ if model.showZoomControl then
            lazy2 zoomControl model.fullscreen model.svg.scale

          else
            Empty.view
        , lazy svgView model
        , lazy miniMapView model
        ]


miniMapView : Model -> Html Msg
miniMapView model =
    if model.showMiniMap then
        let
            size =
                Utils.getCanvasSize model
                    |> Tuple.mapFirst (\x -> String.fromInt x)
                    |> Tuple.mapSecond (\x -> String.fromInt x)

            newModel =
                { model | x = 0, y = 0, matchParent = True }

            mainSvg =
                case model.diagramType of
                    UserStoryMap ->
                        lazy UserStoryMap.view newModel

                    BusinessModelCanvas ->
                        lazy BusinessModelCanvas.view newModel

                    OpportunityCanvas ->
                        lazy OpportunityCanvas.view newModel

                    FourLs ->
                        lazy FourLs.view newModel

                    StartStopContinue ->
                        lazy StartStopContinue.view newModel

                    Kpt ->
                        lazy Kpt.view newModel

                    UserPersona ->
                        lazy UserPersona.view newModel

                    Markdown ->
                        lazy Markdown.view newModel

                    MindMap ->
                        lazy MindMap.view newModel
        in
        lazy3 MiniMap.view model size mainSvg

    else
        Empty.view


svgView : Model -> Svg Msg
svgView model =
    let
        svgWidth =
            if model.fullscreen then
                Basics.toFloat
                    (Basics.max model.svg.width model.width)
                    * model.svg.scale
                    |> round
                    |> String.fromInt

            else
                Basics.toFloat
                    model.width
                    * model.svg.scale
                    |> round
                    |> String.fromInt

        svgHeight =
            if model.fullscreen then
                Basics.toFloat
                    (Basics.max model.svg.height model.height)
                    * model.svg.scale
                    |> round
                    |> String.fromInt

            else
                Basics.toFloat
                    model.height
                    * model.svg.scale
                    |> round
                    |> String.fromInt

        mainSvg =
            case model.diagramType of
                UserStoryMap ->
                    lazy UserStoryMap.view model

                BusinessModelCanvas ->
                    lazy BusinessModelCanvas.view model

                OpportunityCanvas ->
                    lazy OpportunityCanvas.view model

                FourLs ->
                    lazy FourLs.view model

                StartStopContinue ->
                    lazy StartStopContinue.view model

                Kpt ->
                    lazy Kpt.view model

                UserPersona ->
                    lazy UserPersona.view model

                Markdown ->
                    lazy Markdown.view model

                MindMap ->
                    lazy MindMap.view model
    in
    svg
        [ Attr.id "usm"
        , width
            (String.fromInt
                (if Utils.isPhone model.width || model.fullscreen then
                    model.width

                 else if model.width - 56 > 0 then
                    model.width - 56

                 else
                    0
                )
            )
        , height
            (String.fromInt <|
                if model.fullscreen then
                    model.height + 56

                else
                    model.height
            )
        , viewBox ("0 0 " ++ svgWidth ++ " " ++ svgHeight)
        , Attr.style "background-color" model.settings.backgroundColor
        , Wheel.onWheel chooseZoom
        , onDragStart (Utils.isPhone model.width)
        , if model.moveStart then
            onDragMove model.touchDistance (Utils.isPhone model.width)

          else
            Attr.style "" ""
        ]
        [ if String.isEmpty model.settings.font then
            g [] []

          else
            defs []
                [ Svg.style
                    []
                    [ text ("@import url('https://fonts.googleapis.com/css?family=" ++ model.settings.font ++ "&display=swap');") ]
                ]
        , mainSvg
        ]


calcDistance : ( Float, Float ) -> ( Float, Float ) -> Float
calcDistance p1 p2 =
    let
        ( x1, y1 ) =
            p1

        ( x2, y2 ) =
            p2
    in
    sqrt (((x2 - x1) ^ 2) + ((y2 - y1) ^ 2))


onDragStart : Bool -> Attribute Msg
onDragStart isPhone =
    if isPhone then
        Touch.onStart
            (\event ->
                if List.length event.changedTouches > 1 then
                    let
                        p1 =
                            getAt 0 event.changedTouches
                                |> Maybe.map .pagePos
                                |> Maybe.withDefault ( 0, 0 )

                        p2 =
                            getAt 1 event.changedTouches
                                |> Maybe.map .pagePos
                                |> Maybe.withDefault ( 0, 0 )
                    in
                    StartPinch (calcDistance p1 p2)

                else
                    let
                        ( x, y ) =
                            touchCoordinates event
                    in
                    Start (round x) (round y)
            )

    else
        Mouse.onDown
            (\event ->
                let
                    ( x, y ) =
                        event.pagePos
                in
                Start (round x) (round y)
            )


onDragMove : Maybe Float -> Bool -> Attribute Msg
onDragMove distance isPhone =
    if isPhone then
        Touch.onMove
            (\event ->
                if List.length event.changedTouches > 1 then
                    let
                        p1 =
                            getAt 0 event.changedTouches
                                |> Maybe.map .pagePos
                                |> Maybe.withDefault ( 0, 0 )

                        p2 =
                            getAt 1 event.changedTouches
                                |> Maybe.map .pagePos
                                |> Maybe.withDefault ( 0, 0 )
                    in
                    case distance of
                        Just x ->
                            let
                                newDistance =
                                    calcDistance p1 p2
                            in
                            if newDistance / x > 1.0 then
                                PinchIn newDistance

                            else if newDistance / x < 1.0 then
                                PinchOut newDistance

                            else
                                NoOp

                        Nothing ->
                            StartPinch (calcDistance p1 p2)

                else
                    let
                        ( x, y ) =
                            touchCoordinates event
                    in
                    Move (round x) (round y)
            )

    else
        Mouse.onMove
            (\event ->
                let
                    ( x, y ) =
                        event.pagePos
                in
                Move (round x) (round y)
            )


chooseZoom : Wheel.Event -> Msg
chooseZoom wheelEvent =
    if wheelEvent.deltaY > 0 then
        ZoomOut

    else
        ZoomIn


touchCoordinates : Touch.Event -> ( Float, Float )
touchCoordinates touchEvent =
    List.head touchEvent.changedTouches
        |> Maybe.map .clientPos
        |> Maybe.withDefault ( 0, 0 )



-- Update


updateDiagram : Size -> Int -> Int -> Model -> String -> Result String Model
updateDiagram size width height base text =
    load base.diagramType text
        |> Result.andThen
            (\( hierarchy, items ) ->
                let
                    labels =
                        Parser.parseComment text
                            |> List.filter
                                (\( k, _ ) ->
                                    k == "labels"
                                )
                            |> List.map Tuple.second
                            |> List.head
                            |> Maybe.andThen
                                (\v ->
                                    Just (String.split "," v)
                                )
                            |> Maybe.withDefault []

                    itemCount =
                        Basics.max (List.length items)
                            (items
                                |> List.map
                                    (\it ->
                                        Item.unwrapChildren it.children |> List.length
                                    )
                                |> List.sum
                            )

                    countByHierarchy =
                        case base.diagramType of
                            UserStoryMap ->
                                countUpToHierarchy (hierarchy - 2) items

                            MindMap ->
                                countUpToHierarchy (hierarchy - 2) items

                            _ ->
                                []

                    svgWidth =
                        itemCount * (size.width + itemMargin) + leftMargin * 2

                    svgHeight =
                        (countByHierarchy
                            |> List.sum
                        )
                            * (size.height + (itemMargin + 2))
                            + itemMargin
                            + size.height

                    countByTasks =
                        scanl (\it v -> v + List.length (Item.unwrapChildren it.children)) 0 items
                in
                Ok
                    { hierarchy = hierarchy
                    , items = items
                    , width = width
                    , height = height
                    , svg =
                        { width = svgWidth
                        , height = svgHeight
                        , scale = base.svg.scale
                        }
                    , countByHierarchy = countByHierarchy
                    , countByTasks = countByTasks
                    , moveStart = base.moveStart
                    , x = base.x
                    , y = base.y
                    , moveX = 0
                    , moveY = 0
                    , fullscreen = base.fullscreen
                    , settings = base.settings
                    , error = Nothing
                    , showZoomControl = base.showZoomControl
                    , touchDistance = base.touchDistance
                    , diagramType = base.diagramType
                    , labels = labels
                    , text =
                        if String.isEmpty text then
                            Nothing

                        else
                            Just text
                    , showMiniMap = base.showMiniMap
                    , matchParent = base.matchParent
                    }
            )


update : Msg -> Model -> Model
update message model =
    case message of
        NoOp ->
            model

        Init settings window text ->
            let
                width =
                    round window.viewport.width

                height =
                    round window.viewport.height - 50

                result =
                    updateDiagram settings.size width height model text
            in
            case result of
                Ok usm ->
                    { usm | settings = settings, error = Nothing }

                Err err ->
                    { model | error = Just err }

        ZoomIn ->
            if model.svg.scale > 0.1 then
                { model
                    | svg =
                        { width = model.svg.width
                        , height = model.svg.height
                        , scale = model.svg.scale - 0.05
                        }
                }

            else
                model

        ZoomOut ->
            if model.svg.scale < 2.0 then
                { model
                    | svg =
                        { width = model.svg.width
                        , height = model.svg.height
                        , scale = model.svg.scale + 0.05
                        }
                }

            else
                model

        PinchIn distance ->
            { model | touchDistance = Just distance }

        PinchOut distance ->
            { model | touchDistance = Just distance }

        OnChangeText text ->
            let
                result =
                    updateDiagram model.settings.size model.width model.height model text
            in
            case result of
                Ok usm ->
                    { usm | error = Nothing }

                Err err ->
                    { model | error = Just err }

        Start x y ->
            { model
                | moveStart = True
                , moveX = x
                , moveY = y
            }

        Stop ->
            { model
                | moveStart = False
                , moveX = 0
                , moveY = 0
                , touchDistance = Nothing
            }

        Move x y ->
            if not model.moveStart || (x == model.moveX && y == model.moveY) then
                model

            else
                { model
                    | x = model.x + (x - model.moveX)
                    , y = model.y + (y - model.moveY)
                    , moveX = x
                    , moveY = y
                }

        MoveTo x y ->
            { model
                | x = x
                , y = y
                , moveX = 0
                , moveY = 0
            }

        ToggleFullscreen ->
            { model
                | moveX = 0
                , moveY = 0
                , fullscreen = not model.fullscreen
            }

        OnResize width height ->
            { model
                | width = width
                , height = height - 56
                , moveX = 0
                , moveY = 0
            }

        StartPinch distance ->
            { model | touchDistance = Just distance }

        _ ->
            model
