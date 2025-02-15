module Views.Diagram.ImpactMap exposing (view)

import Data.Item as Item exposing (Item, ItemType(..), Items)
import Data.ItemSettings as ItemSettings
import Data.Position as Position exposing (Position)
import Data.Size exposing (Size)
import List.Extra as ListEx
import Models.Diagram as Diagram exposing (Model, Msg(..), SelectedItem, Settings)
import Svg exposing (Svg)
import Views.Diagram.Path as Path
import Views.Diagram.Views as Views
import Views.Empty as Empty


xMargin : Int
xMargin =
    100


yMargin : Int
yMargin =
    10


view : Model -> Svg Msg
view model =
    case model.data of
        Diagram.ImpactMap items _ ->
            let
                rootItem =
                    Item.head items

                moveingItem =
                    Diagram.moveingItem model
            in
            case rootItem of
                Just root ->
                    let
                        impactMapItems =
                            Item.unwrapChildren <| Item.getChildren root
                    in
                    Svg.g
                        []
                        [ nodesView
                            { settings = model.settings
                            , hierarchy = 2
                            , position = Position.zero
                            , selectedItem = model.selectedItem
                            , moveingItem = moveingItem
                            , items = impactMapItems
                            }
                        , Views.rootTextNode
                            { settings = model.settings
                            , position = Position.zero
                            , selectedItem = model.selectedItem
                            , item = root
                            }
                        ]

                Nothing ->
                    Svg.g [] []

        _ ->
            Empty.view


nodesView :
    { settings : Settings
    , hierarchy : Int
    , position : Position
    , selectedItem : SelectedItem
    , moveingItem : Maybe Item
    , items : Items
    }
    -> Svg Msg
nodesView { settings, hierarchy, position, selectedItem, items, moveingItem } =
    let
        svgWidth =
            settings.size.width

        svgHeight =
            settings.size.height

        ( x, y ) =
            position

        tmpNodeCounts =
            items
                |> Item.map
                    (\i ->
                        if Item.isEmpty (Item.unwrapChildren <| Item.getChildren i) then
                            0

                        else
                            Item.getChildrenCount i
                    )
                |> List.concatMap
                    (\count ->
                        let
                            v =
                                round <| toFloat count / 2.0
                        in
                        [ v, v ]
                    )
                |> ListEx.scanl1 (+)

        nodeCounts =
            tmpNodeCounts
                |> List.indexedMap (\i _ -> i)
                |> List.filter (\i -> i == 0 || modBy 2 i == 0)
                |> List.map (\i -> ListEx.getAt i tmpNodeCounts |> Maybe.withDefault 1)
                |> List.indexedMap (\i v -> v + i + 1)

        yOffset =
            List.sum nodeCounts // List.length nodeCounts * svgHeight

        range =
            List.range 0 (List.length nodeCounts)
    in
    Svg.g []
        (ListEx.zip3 range nodeCounts (Item.unwrap items)
            |> List.concatMap
                (\( i, nodeCount, item ) ->
                    let
                        offset =
                            Maybe.map
                                (\m ->
                                    if Item.getLineNo m == Item.getLineNo item then
                                        m

                                    else
                                        item
                                )
                                moveingItem
                                |> Maybe.withDefault item
                                |> Item.getItemSettings
                                |> Maybe.map ItemSettings.getOffset
                                |> Maybe.withDefault Position.zero

                        itemX =
                            x + (svgWidth + xMargin) + Position.getX offset

                        itemY =
                            y + (nodeCount * svgHeight - yOffset) + (i * yMargin) + Position.getY offset
                    in
                    [ nodeLineView
                        ( settings.size.width, settings.size.height )
                        settings.color.task.backgroundColor
                        ( x, y )
                        ( itemX, itemY )
                    , nodesView
                        { settings = settings
                        , hierarchy = hierarchy + 1
                        , position =
                            ( itemX
                            , itemY
                            )
                        , selectedItem = selectedItem
                        , moveingItem = moveingItem
                        , items = Item.unwrapChildren <| Item.getChildren item
                        }
                    , Views.node settings
                        ( itemX, itemY )
                        selectedItem
                        item
                    ]
                )
        )


nodeLineView : Size -> String -> Position -> Position -> Svg Msg
nodeLineView ( width, height ) colour fromBase toBase =
    let
        ( fromPoint, toPoint ) =
            ( Tuple.mapBoth toFloat toFloat fromBase, Tuple.mapBoth toFloat toFloat toBase )

        size =
            ( toFloat width, toFloat height )
    in
    Path.view colour
        ( fromPoint, size )
        ( toPoint, size )
