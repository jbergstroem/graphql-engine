import { configSchema } from "./config"
import { Capabilities, CapabilitiesResponse, ScalarTypeCapabilities, ScalarTypesCapabilities } from "@hasura/dc-api-types"

const schemaDoc: string =
  `scalar DateTime

input DateTimeComparisons {
  same_day_as: DateTime
  in_year: Int
}`

const dateTimeCapabilities: ScalarTypeCapabilities = {
  comparison_type: 'DateTimeComparisons'
}

const scalarTypes: ScalarTypesCapabilities = {
  DateTime: dateTimeCapabilities
}

const capabilities: Capabilities = {
  relationships: {},
  comparisons: {
    cross_table: {
      supports_relations: true
    }
  },
  graphql_schema: schemaDoc,
  scalar_types: scalarTypes
}

export const capabilitiesResponse: CapabilitiesResponse = {
  capabilities: capabilities,
  config_schemas: configSchema
}
