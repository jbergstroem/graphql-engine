{-# LANGUAGE QuasiQuotes #-}

module Test.Specs.QuerySpec.AggregatesSpec (spec) where

import Control.Arrow ((>>>))
import Control.Lens (ix, (%~), (&), (.~), (?~), (^?), _Just)
import Control.Monad (when)
import Data.Aeson (Value (..))
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.HashSet qualified as HashSet
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Ord (Down (..))
import Hasura.Backends.DataConnector.API
import Language.GraphQL.Draft.Syntax.QQ qualified as G
import Test.AgentClient (queryGuarded)
import Test.Data (TestData (..))
import Test.Data qualified as Data
import Test.Expectations (jsonShouldBe, rowsShouldBe)
import Test.Sandwich (describe)
import Test.TestHelpers (AgentTestSpec, it)
import Prelude

spec :: TestData -> SourceName -> Config -> Maybe RelationshipCapabilities -> AgentTestSpec
spec TestData {..} sourceName config relationshipCapabilities = describe "Aggregate Queries" $ do
  describe "Star Count" $ do
    it "counts all rows" $ do
      let aggregates = Data.mkFieldsMap [("count_all", StarCount)]
      let queryRequest = invoicesQueryRequest aggregates
      response <- queryGuarded sourceName config queryRequest

      let invoiceCount = length _tdInvoicesRows
      let expectedAggregates = Data.mkFieldsMap [("count_all", Number $ fromIntegral invoiceCount)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "counts all rows, after applying filters" $ do
      let where' = ApplyBinaryComparisonOperator Equal (_tdCurrentComparisonColumn "BillingCity" _tdStringType) (ScalarValue (String "Oslo") _tdStringType)
      let aggregates = Data.mkFieldsMap [("count_all", StarCount)]
      let queryRequest = invoicesQueryRequest aggregates & qrQuery . qWhere ?~ where'
      response <- queryGuarded sourceName config queryRequest

      let invoiceCount = length $ filter ((^? Data.field "BillingCity" . Data._ColumnFieldString) >>> (== Just "Oslo")) _tdInvoicesRows
      let expectedAggregates = Data.mkFieldsMap [("count_all", Number $ fromIntegral invoiceCount)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "counts all rows, after applying pagination" $ do
      let offset = 400
      let limit = 20
      let aggregates = Data.mkFieldsMap [("count_all", StarCount)]
      let queryRequest = invoicesQueryRequest aggregates & qrQuery %~ (qLimit ?~ limit >>> qOffset ?~ offset)
      response <- queryGuarded sourceName config queryRequest

      let invoiceCount = length . take limit $ drop offset _tdInvoicesRows
      let expectedAggregates = Data.mkFieldsMap [("count_all", Number $ fromIntegral invoiceCount)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

  describe "Column Count" $ do
    it "counts all rows with non-null columns" $ do
      let aggregates = Data.mkFieldsMap [("count_cols", ColumnCount $ ColumnCountAggregate (_tdColumnName "BillingState") False)]
      let queryRequest = invoicesQueryRequest aggregates
      response <- queryGuarded sourceName config queryRequest

      let invoiceCount = length $ filter ((^? Data.field "BillingState" . Data._ColumnFieldString) >>> (/= Nothing)) _tdInvoicesRows
      let expectedAggregates = Data.mkFieldsMap [("count_cols", Number $ fromIntegral invoiceCount)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "can count all rows with non-null values in a column, after applying pagination and filtering" $ do
      let limit = 50
      let where' = ApplyBinaryComparisonOperator GreaterThanOrEqual (_tdCurrentComparisonColumn "InvoiceId" _tdIntType) (ScalarValue (Number 380) _tdIntType)
      let aggregates = Data.mkFieldsMap [("count_cols", ColumnCount $ ColumnCountAggregate (_tdColumnName "BillingState") False)]
      let queryRequest = invoicesQueryRequest aggregates & qrQuery %~ (qLimit ?~ limit >>> qWhere ?~ where')
      response <- queryGuarded sourceName config queryRequest

      let invoiceCount =
            _tdInvoicesRows
              & filter ((^? Data.field "InvoiceId" . Data._ColumnFieldNumber) >>> (>= Just 380))
              & take limit
              & mapMaybe ((^? Data.field "BillingState" . Data._ColumnFieldString))
              & length

      let expectedAggregates = Data.mkFieldsMap [("count_cols", Number $ fromIntegral invoiceCount)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "can count all rows with distinct non-null values in a column" $ do
      let aggregates = Data.mkFieldsMap [("count_cols", ColumnCount $ ColumnCountAggregate (_tdColumnName "BillingState") True)]
      let queryRequest = invoicesQueryRequest aggregates
      response <- queryGuarded sourceName config queryRequest

      let billingStateCount = length . HashSet.fromList $ mapMaybe ((^? Data.field "BillingState" . Data._ColumnFieldString)) _tdInvoicesRows
      let expectedAggregates = Data.mkFieldsMap [("count_cols", Number $ fromIntegral billingStateCount)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "can count all rows with distinct non-null values in a column, after applying pagination and filtering" $ do
      let limit = 20
      let where' = ApplyBinaryComparisonOperator GreaterThanOrEqual (_tdCurrentComparisonColumn "InvoiceId" _tdIntType) (ScalarValue (Number 380) _tdIntType)
      -- It is important to add an explicit order by for this query as different database engines will order implicitly resulting in incorrect results
      let orderBy = OrderBy mempty $ _tdOrderByColumn [] "InvoiceId" Ascending :| []
      let aggregates = Data.mkFieldsMap [("count_cols", ColumnCount $ ColumnCountAggregate (_tdColumnName "BillingState") True)]
      let queryRequest = invoicesQueryRequest aggregates & qrQuery %~ (qLimit ?~ limit >>> qWhere ?~ where' >>> qOrderBy ?~ orderBy)
      response <- queryGuarded sourceName config queryRequest

      let billingStateCount =
            _tdInvoicesRows
              & filter ((^? Data.field "InvoiceId" . Data._ColumnFieldNumber) >>> (>= Just 380))
              & take limit
              & mapMaybe ((^? Data.field "BillingState" . Data._ColumnFieldString))
              & HashSet.fromList
              & length

      let expectedAggregates = Data.mkFieldsMap [("count_cols", Number $ fromIntegral billingStateCount)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

  describe "Single Column Function" $ do
    it "can get the max total from all rows" $ do
      let aggregates = Data.mkFieldsMap [("max", singleColumnAggregateMax (_tdColumnName "Total"))]
      let queryRequest = invoicesQueryRequest aggregates
      response <- queryGuarded sourceName config queryRequest

      let maxTotal = maximum $ mapMaybe ((^? Data.field "Total" . Data._ColumnFieldNumber)) _tdInvoicesRows
      let expectedAggregates = Data.mkFieldsMap [("max", Number maxTotal)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "can get the max total from all rows, after applying pagination, filtering and ordering" $ do
      let limit = 20
      let where' = ApplyBinaryComparisonOperator Equal (_tdCurrentComparisonColumn "BillingCountry" _tdStringType) (ScalarValue (String "USA") _tdStringType)
      let orderBy = OrderBy mempty $ _tdOrderByColumn [] "BillingPostalCode" Descending :| [_tdOrderByColumn [] "InvoiceId" Ascending]
      let aggregates = Data.mkFieldsMap [("max", singleColumnAggregateMax (_tdColumnName "Total"))]
      let queryRequest = invoicesQueryRequest aggregates & qrQuery %~ (qLimit ?~ limit >>> qWhere ?~ where' >>> qOrderBy ?~ orderBy)
      response <- queryGuarded sourceName config queryRequest

      let maxTotal =
            _tdInvoicesRows
              & filter ((^? Data.field "BillingCountry" . Data._ColumnFieldString) >>> (== Just "USA"))
              & sortOn (Down . (^? Data.field "BillingPostalCode"))
              & take limit
              & mapMaybe ((^? Data.field "Total" . Data._ColumnFieldNumber))
              & maximum

      let expectedAggregates = Data.mkFieldsMap [("max", Number maxTotal)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "can get the min and max of a non-numeric comparable type such as a string" $ do
      let aggregates =
            Data.mkFieldsMap
              [ ("min", singleColumnAggregateMin (_tdColumnName "Name")),
                ("max", singleColumnAggregateMax (_tdColumnName "Name"))
              ]
      let queryRequest = artistsQueryRequest aggregates
      response <- queryGuarded sourceName config queryRequest

      let names = mapMaybe ((^? Data.field "Name" . Data._ColumnFieldString)) _tdArtistsRows
      let expectedAggregates =
            Data.mkFieldsMap
              [ ("min", aggregate (String . minimum) names),
                ("max", aggregate (String . maximum) names)
              ]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "aggregates over empty row lists results in nulls" $ do
      let where' = ApplyBinaryComparisonOperator LessThan (_tdCurrentComparisonColumn "ArtistId" _tdIntType) (ScalarValue (Number 0) _tdIntType)
      let aggregates = Data.mkFieldsMap [("min", singleColumnAggregateMin (_tdColumnName "Name"))]
      let queryRequest = artistsQueryRequest aggregates & qrQuery . qWhere ?~ where'
      response <- queryGuarded sourceName config queryRequest

      let expectedAggregates = Data.mkFieldsMap [("min", Null)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

  describe "Multiple Aggregates and Returning Rows" $ do
    it "can get the max total from all rows, the count and the distinct count, simultaneously" $ do
      let aggregates =
            Data.mkFieldsMap
              [ ("count", StarCount),
                ("distinctBillingStates", ColumnCount $ ColumnCountAggregate (_tdColumnName "BillingState") True),
                ("maxTotal", singleColumnAggregateMax (_tdColumnName "Total"))
              ]
      let queryRequest = invoicesQueryRequest aggregates
      response <- queryGuarded sourceName config queryRequest

      let invoiceCount = length _tdInvoicesRows
      let billingStateCount = length . HashSet.fromList $ mapMaybe ((^? Data.field "BillingState" . Data._ColumnFieldString)) _tdInvoicesRows
      let maxTotal = aggregate (Number . maximum) $ mapMaybe ((^? Data.field "Total" . Data._ColumnFieldNumber)) _tdInvoicesRows

      let expectedAggregates =
            Data.mkFieldsMap
              [ ("count", Number $ fromIntegral invoiceCount),
                ("distinctBillingStates", Number $ fromIntegral billingStateCount),
                ("maxTotal", maxTotal)
              ]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "can reuse the same aggregate twice" $ do
      let aggregates =
            Data.mkFieldsMap
              [ ("minInvoiceId", singleColumnAggregateMin (_tdColumnName "InvoiceId")),
                ("minTotal", singleColumnAggregateMin (_tdColumnName "Total"))
              ]
      let queryRequest = invoicesQueryRequest aggregates
      response <- queryGuarded sourceName config queryRequest

      let maxInvoiceId = aggregate (Number . minimum) $ mapMaybe ((^? Data.field "InvoiceId" . Data._ColumnFieldNumber)) _tdInvoicesRows
      let maxTotal = aggregate (Number . minimum) $ mapMaybe ((^? Data.field "Total" . Data._ColumnFieldNumber)) _tdInvoicesRows

      let expectedAggregates =
            Data.mkFieldsMap
              [ ("minInvoiceId", maxInvoiceId),
                ("minTotal", maxTotal)
              ]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    it "can also query for the rows involved in the aggregate" $ do
      let limit = 30
      let fields =
            Data.mkFieldsMap
              [ ("InvoiceId", _tdColumnField "InvoiceId" _tdIntType),
                ("BillingCountry", _tdColumnField "BillingCountry" _tdStringType)
              ]
      let where' = ApplyBinaryComparisonOperator Equal (_tdCurrentComparisonColumn "BillingCountry" _tdStringType) (ScalarValue (String "Canada") _tdStringType)
      let orderBy = OrderBy mempty $ _tdOrderByColumn [] "BillingAddress" Ascending :| [_tdOrderByColumn [] "InvoiceId" Ascending]
      let aggregates = Data.mkFieldsMap [("min", singleColumnAggregateMin (_tdColumnName "Total"))]
      let queryRequest = invoicesQueryRequest aggregates & qrQuery %~ (qFields ?~ fields >>> qLimit ?~ limit >>> qWhere ?~ where' >>> qOrderBy ?~ orderBy)
      response <- queryGuarded sourceName config queryRequest

      let invoiceRows =
            _tdInvoicesRows
              & filter ((^? Data.field "BillingCountry" . Data._ColumnFieldString) >>> (== Just "Canada"))
              & sortOn (^? Data.field "BillingAddress")
              & take limit

      let maxTotal =
            invoiceRows
              & mapMaybe ((^? Data.field "Total" . Data._ColumnFieldNumber))
              & aggregate (Number . minimum)

      let expectedAggregates = Data.mkFieldsMap [("min", maxTotal)]
      let expectedRows = Data.filterColumnsByQueryFields (_qrQuery queryRequest) <$> invoiceRows

      Data.responseRows response `rowsShouldBe` expectedRows
      Data.responseAggregates response `jsonShouldBe` expectedAggregates

  when (isJust relationshipCapabilities) $
    describe "Aggregates via Relationships" $ do
      it "can query aggregates via an array relationship" $ do
        let limit = 5
        let query = artistsWithAlbumsQuery id & qrQuery . qLimit ?~ limit
        receivedArtists <- queryGuarded sourceName config query

        let joinInAlbums (artist :: HashMap FieldName FieldValue) = fromMaybe artist $ do
              artistId <- artist ^? Data.field "ArtistId" . Data._ColumnFieldNumber
              let albums =
                    _tdAlbumsRows
                      & filter ((^? Data.field "ArtistId" . Data._ColumnFieldNumber) >>> (== Just artistId))
              let aggregates = Data.mkFieldsMap [("count", Number . fromIntegral $ length albums)]
              pure $ Data.insertField "Albums" (mkSubqueryResponse Nothing (Just aggregates)) artist

        let expectedArtists =
              _tdArtistsRows
                & take limit
                & fmap joinInAlbums

        Data.responseRows receivedArtists `rowsShouldBe` expectedArtists
        Data.responseAggregates receivedArtists `jsonShouldBe` mempty

      it "can query aggregates via an array relationship and include the rows in that relationship" $ do
        let limit = 5
        let albumFields =
              Data.mkFieldsMap
                [ ("AlbumId", _tdColumnField "AlbumId" _tdIntType),
                  ("Title", _tdColumnField "Title" _tdStringType)
                ]
        let query = artistsWithAlbumsQuery (qFields ?~ albumFields) & qrQuery . qLimit ?~ limit
        receivedArtists <- queryGuarded sourceName config query

        let joinInAlbums (artist :: HashMap FieldName FieldValue) = fromMaybe artist $ do
              artistId <- artist ^? Data.field "ArtistId" . Data._ColumnFieldNumber
              let albums =
                    _tdAlbumsRows
                      & filter ((^? Data.field "ArtistId" . Data._ColumnFieldNumber) >>> (== Just artistId))
                      & Data.filterColumns ["AlbumId", "Title"]
              let aggregates = Data.mkFieldsMap [("count", Number . fromIntegral $ length albums)]
              pure $ Data.insertField "Albums" (mkSubqueryResponse (Just albums) (Just aggregates)) artist

        let sortAlbums (artistRows :: [HashMap FieldName FieldValue]) =
              artistRows & traverse . Data.field "Albums" . Data._RelationshipFieldRows %~ sortOn (^? Data.field "AlbumId")

        let expectedArtists =
              _tdArtistsRows
                & take limit
                & fmap joinInAlbums
                & sortAlbums

        -- Ignore the sort order of the related albums by sorting them in the response and the expected data
        let receivedArtistRows = sortAlbums $ Data.responseRows receivedArtists

        receivedArtistRows `rowsShouldBe` expectedArtists
        Data.responseAggregates receivedArtists `jsonShouldBe` mempty

      it "can query with many nested relationships, with aggregates at multiple levels, with filtering, pagination and ordering" $ do
        receivedArtists <- queryGuarded sourceName config deeplyNestedArtistsQuery

        let joinInMediaType (track :: HashMap FieldName FieldValue) = fromMaybe track $ do
              mediaTypeId <- track ^? Data.field "MediaTypeId" . Data._ColumnFieldNumber
              let mediaTypes =
                    _tdMediaTypesRows
                      & filter ((^? Data.field "MediaTypeId" . Data._ColumnFieldNumber) >>> (== Just mediaTypeId))
                      & Data.filterColumns ["Name"]
              pure $ Data.insertField "nodes_MediaType" (mkSubqueryResponse (Just mediaTypes) Nothing) track

        let joinInInvoiceLines (track :: HashMap FieldName FieldValue) = fromMaybe track $ do
              trackId <- track ^? Data.field "TrackId" . Data._ColumnFieldNumber
              let invoiceLines =
                    _tdInvoiceLinesRows
                      & filter ((^? Data.field "TrackId" . Data._ColumnFieldNumber) >>> (== Just trackId))
              let getQuantity invoiceLine = invoiceLine ^? Data.field "Quantity" . Data._ColumnFieldNumber
              let invoiceLinesAggregates = Data.mkFieldsMap [("aggregate_sum_Quantity", aggregate (Number . sum) $ mapMaybe getQuantity invoiceLines)]
              pure $ Data.insertField "nodes_InvoiceLines_aggregate" (mkSubqueryResponse Nothing (Just invoiceLinesAggregates)) track

        let joinInTracks (album :: HashMap FieldName FieldValue) = fromMaybe album $ do
              albumId <- album ^? Data.field "AlbumId" . Data._ColumnFieldNumber
              let tracks =
                    _tdTracksRows
                      & filter
                        ( \track ->
                            track ^? Data.field "AlbumId" . Data._ColumnFieldNumber == Just albumId
                              && track ^? Data.field "Milliseconds" . Data._ColumnFieldNumber < Just 300000
                        )
                      & sortOn (Down . (^? Data.field "Name" . Data._ColumnFieldString))
                      & fmap (joinInMediaType >>> joinInInvoiceLines)
                      & Data.renameColumns [("Name", "nodes_Name")]
                      & Data.filterColumns ["nodes_Name", "nodes_MediaType", "nodes_InvoiceLines_aggregate"]
              let tracksAggregates = Data.mkFieldsMap [("aggregate_count", Number . fromIntegral $ length tracks)]
              pure $ Data.insertField "nodes_Tracks_aggregate" (mkSubqueryResponse (Just tracks) (Just tracksAggregates)) album

        let joinInAlbums (artist :: HashMap FieldName FieldValue) = fromMaybe artist $ do
              artistId <- artist ^? Data.field "ArtistId" . Data._ColumnFieldNumber
              let albums =
                    _tdAlbumsRows
                      & filter ((^? Data.field "ArtistId" . Data._ColumnFieldNumber) >>> (== Just artistId))
                      & sortOn (^? Data.field "Title" . Data._ColumnFieldString)
                      & fmap joinInTracks
                      & Data.renameColumns [("Title", "nodes_Title")]
                      & Data.filterColumns ["nodes_Title", "nodes_Tracks_aggregate"]
              pure $ Data.insertField "Albums_aggregate" (mkSubqueryResponse (Just albums) Nothing) artist

        let expectedArtists =
              _tdArtistsRows
                & sortOn (Down . (^? Data.field "Name"))
                & filter ((^? Data.field "Name" . Data._ColumnFieldString) >>> (\name -> name > Just "A" && name < Just "B"))
                & drop 1
                & take 3
                & fmap joinInAlbums
                & Data.filterColumns ["Name", "Albums_aggregate"]

        let receivedArtistRows = Data.responseRows receivedArtists

        receivedArtistRows `rowsShouldBe` expectedArtists
        Data.responseAggregates receivedArtists `jsonShouldBe` mempty

  describe "Aggregates over ordered and paginated tables" $ do
    it "orders by a column" $ do
      let offset = 2
      let limit = 5
      let orderBy = OrderBy mempty $ _tdOrderByColumn [] "Title" Descending :| []
      let aggregates = Data.mkFieldsMap [("max", singleColumnAggregateMax (_tdColumnName "Title"))]
      let queryRequest =
            albumsQueryRequest
              & qrQuery
                %~ ( qAggregates ?~ aggregates
                       >>> qOrderBy ?~ orderBy
                       >>> qOffset ?~ offset
                       >>> qLimit ?~ limit
                   )
      response <- queryGuarded sourceName config queryRequest

      let names =
            _tdAlbumsRows
              & sortOn (Down . (^? Data.field "Title"))
              & drop offset
              & take limit
              & mapMaybe (^? Data.field "Title" . Data._ColumnFieldString)

      let expectedAggregates = Data.mkFieldsMap [("max", aggregate (String . maximum) names)]

      Data.responseAggregates response `jsonShouldBe` expectedAggregates
      Data.responseRows response `rowsShouldBe` []

    when (isJust relationshipCapabilities) . describe "involving related tables in the ordering" $ do
      it "orders by a column" $ do
        let offset = 10
        let limit = 50
        let orderByRelations = HashMap.fromList [(_tdArtistRelationshipName, OrderByRelation Nothing mempty)]
        let orderBy =
              OrderBy orderByRelations $
                NonEmpty.fromList
                  [ _tdOrderByColumn [_tdArtistRelationshipName] "Name" Ascending,
                    _tdOrderByColumn [] "AlbumId" Ascending
                  ]
        let aggregates = Data.mkFieldsMap [("max", singleColumnAggregateMax (_tdColumnName "Title"))]
        let queryRequest =
              albumsQueryRequest
                & qrTableRelationships .~ [Data.onlyKeepRelationships [_tdArtistRelationshipName] _tdAlbumsTableRelationships]
                & qrQuery
                  %~ ( qAggregates ?~ aggregates
                         >>> qOrderBy ?~ orderBy
                         >>> qOffset ?~ offset
                         >>> qLimit ?~ limit
                     )
        response <- queryGuarded sourceName config queryRequest

        let getRelatedArtist (album :: HashMap FieldName FieldValue) =
              (album ^? Data.field "ArtistId" . Data._ColumnFieldNumber) >>= \artistId -> _tdArtistsRowsById ^? ix artistId

        let names =
              _tdAlbumsRows
                & sortOn (\album -> getRelatedArtist album ^? _Just . Data.field "Name")
                & drop offset
                & take limit
                & mapMaybe (^? Data.field "Title" . Data._ColumnFieldString)

        let expectedAggregates = Data.mkFieldsMap [("max", aggregate (String . maximum) names)]

        Data.responseAggregates response `jsonShouldBe` expectedAggregates
        Data.responseRows response `rowsShouldBe` []

      it "orders by an aggregate" $ do
        let offset = 15
        let limit = 10
        let orderByRelations = HashMap.fromList [(_tdTracksRelationshipName, OrderByRelation Nothing mempty)]
        let orderBy =
              OrderBy orderByRelations $
                NonEmpty.fromList
                  [ OrderByElement [_tdTracksRelationshipName] OrderByStarCountAggregate Descending,
                    _tdOrderByColumn [] "Title" Descending
                  ]
        let aggregates = Data.mkFieldsMap [("max", singleColumnAggregateMax (_tdColumnName "Title"))]
        let queryRequest =
              albumsQueryRequest
                & qrTableRelationships .~ [Data.onlyKeepRelationships [_tdTracksRelationshipName] _tdAlbumsTableRelationships]
                & qrQuery
                  %~ ( qAggregates ?~ aggregates
                         >>> qOrderBy ?~ orderBy
                         >>> qOffset ?~ offset
                         >>> qLimit ?~ limit
                     )
        response <- queryGuarded sourceName config queryRequest

        let getRelatedTracksCount (album :: HashMap FieldName FieldValue) = fromMaybe 0 $ do
              albumId <- (album ^? Data.field "AlbumId" . Data._ColumnFieldNumber)
              _tdTracksRows & filter (\track -> track ^? Data.field "AlbumId" . Data._ColumnFieldNumber == Just albumId) & length & pure

        let names =
              _tdAlbumsRows
                & sortOn (\album -> (Down $ getRelatedTracksCount album, Down $ album ^? Data.field "Title" . Data._ColumnFieldString))
                & drop offset
                & take limit
                & mapMaybe (^? Data.field "Title" . Data._ColumnFieldString)

        let expectedAggregates = Data.mkFieldsMap [("max", aggregate (String . maximum) names)]

        Data.responseAggregates response `jsonShouldBe` expectedAggregates
        Data.responseRows response `rowsShouldBe` []
  where
    artistsWithAlbumsQuery :: (Query -> Query) -> QueryRequest
    artistsWithAlbumsQuery modifySubquery =
      let albumAggregates = Data.mkFieldsMap [("count", StarCount)]
          albumsSubquery = Data.emptyQuery & qAggregates ?~ albumAggregates & modifySubquery
          artistFields =
            Data.mkFieldsMap
              [ ("ArtistId", _tdColumnField "ArtistId" _tdIntType),
                ("Name", _tdColumnField "Name" _tdStringType),
                ("Albums", RelField $ RelationshipField _tdAlbumsRelationshipName albumsSubquery)
              ]
          artistOrderBy = OrderBy mempty $ _tdOrderByColumn [] "ArtistId" Ascending :| []
          artistQuery = Data.emptyQuery & qFields ?~ artistFields & qOrderBy ?~ artistOrderBy
          artistsTableRelationships = Data.onlyKeepRelationships [_tdAlbumsRelationshipName] _tdArtistsTableRelationships
       in QueryRequest _tdArtistsTableName [artistsTableRelationships] artistQuery

    -- This query is basically what would be generated by this complex HGE GraphQL query
    -- @
    --   query {
    --     Artist(where: {_and: [{Name: {_gt: "A"}}, {Name: {_lt: "B"}}]}, limit: 3, offset: 1, order_by: {Name: desc}) {
    --       Name
    --       Albums_aggregate(order_by: {Title: asc}) {
    --         nodes {
    --           Title
    --           Tracks_aggregate(where: {Milliseconds: {_lt: 300000}}, order_by: {Name: desc}) {
    --             aggregate {
    --               count
    --             }
    --             nodes {
    --               Name
    --               MediaType {
    --                 Name
    --               }
    --               InvoiceLines_aggregate {
    --                 aggregate {
    --                   sum {
    --                     Quantity
    --                   }
    --                 }
    --               }
    --             }
    --           }
    --         }
    --       }
    --     }
    --   }
    -- @
    deeplyNestedArtistsQuery :: QueryRequest
    deeplyNestedArtistsQuery =
      let invoiceLinesAggregates = Data.mkFieldsMap [("aggregate_sum_Quantity", singleColumnAggregateSum (_tdColumnName "Quantity"))]
          invoiceLinesSubquery = Data.emptyQuery & qAggregates ?~ invoiceLinesAggregates
          mediaTypeFields = Data.mkFieldsMap [("Name", _tdColumnField "Name" _tdStringType)]
          mediaTypeSubquery = Data.emptyQuery & qFields ?~ mediaTypeFields
          tracksFields =
            Data.mkFieldsMap
              [ ("nodes_Name", _tdColumnField "Name" _tdStringType),
                ("nodes_MediaType", RelField $ RelationshipField _tdMediaTypeRelationshipName mediaTypeSubquery),
                ("nodes_InvoiceLines_aggregate", RelField $ RelationshipField _tdInvoiceLinesRelationshipName invoiceLinesSubquery)
              ]
          tracksAggregates = Data.mkFieldsMap [("aggregate_count", StarCount)]
          tracksWhere = ApplyBinaryComparisonOperator LessThan (_tdCurrentComparisonColumn "Milliseconds" _tdIntType) (ScalarValue (Number 300000) _tdIntType)
          tracksOrderBy = OrderBy mempty $ _tdOrderByColumn [] "Name" Descending :| []
          tracksSubquery = Query (Just tracksFields) (Just tracksAggregates) Nothing Nothing (Just tracksWhere) (Just tracksOrderBy)
          albumsFields =
            Data.mkFieldsMap
              [ ("nodes_Title", _tdColumnField "Title" _tdStringType),
                ("nodes_Tracks_aggregate", RelField $ RelationshipField _tdTracksRelationshipName tracksSubquery)
              ]
          albumsOrderBy = OrderBy mempty $ _tdOrderByColumn [] "Title" Ascending :| []
          albumsSubquery = Data.emptyQuery & qFields ?~ albumsFields & qOrderBy ?~ albumsOrderBy
          artistFields =
            Data.mkFieldsMap
              [ ("Name", _tdColumnField "Name" _tdStringType),
                ("Albums_aggregate", RelField $ RelationshipField _tdAlbumsRelationshipName albumsSubquery)
              ]
          artistWhere =
            And
              [ ApplyBinaryComparisonOperator GreaterThan (_tdCurrentComparisonColumn "Name" _tdStringType) (ScalarValue (String "A") _tdStringType),
                ApplyBinaryComparisonOperator LessThan (_tdCurrentComparisonColumn "Name" _tdStringType) (ScalarValue (String "B") _tdStringType)
              ]
          artistOrderBy = OrderBy mempty $ _tdOrderByColumn [] "Name" Descending :| []
          artistQuery = Query (Just artistFields) Nothing (Just 3) (Just 1) (Just artistWhere) (Just artistOrderBy)
       in QueryRequest
            _tdArtistsTableName
            [ Data.onlyKeepRelationships [_tdAlbumsRelationshipName] _tdArtistsTableRelationships,
              Data.onlyKeepRelationships [_tdTracksRelationshipName] _tdAlbumsTableRelationships,
              Data.onlyKeepRelationships [_tdInvoiceLinesRelationshipName, _tdMediaTypeRelationshipName] _tdTracksTableRelationships
            ]
            artistQuery

    artistsQueryRequest :: HashMap FieldName Aggregate -> QueryRequest
    artistsQueryRequest aggregates =
      let query = Data.emptyQuery & qAggregates ?~ aggregates
       in QueryRequest _tdArtistsTableName [] query

    invoicesQueryRequest :: HashMap FieldName Aggregate -> QueryRequest
    invoicesQueryRequest aggregates =
      let query = Data.emptyQuery & qAggregates ?~ aggregates
       in QueryRequest _tdInvoicesTableName [] query

    albumsQueryRequest :: QueryRequest
    albumsQueryRequest =
      QueryRequest _tdAlbumsTableName [] Data.emptyQuery

    mkSubqueryResponse :: Maybe [HashMap FieldName FieldValue] -> Maybe (HashMap FieldName Value) -> FieldValue
    mkSubqueryResponse rows aggregates =
      mkRelationshipFieldValue $ QueryResponse rows aggregates

    aggregate :: (NonEmpty a -> Value) -> [a] -> Value
    aggregate aggFn values =
      maybe Null aggFn $ NonEmpty.nonEmpty values

    singleColumnAggregateMax :: ColumnName -> Aggregate
    singleColumnAggregateMax = SingleColumn . SingleColumnAggregate (SingleColumnAggregateFunction [G.name|max|])

    singleColumnAggregateMin :: ColumnName -> Aggregate
    singleColumnAggregateMin = SingleColumn . SingleColumnAggregate (SingleColumnAggregateFunction [G.name|min|])

    singleColumnAggregateSum :: ColumnName -> Aggregate
    singleColumnAggregateSum = SingleColumn . SingleColumnAggregate (SingleColumnAggregateFunction [G.name|sum|])