@_exported import HTTP
import GraphQL
import Graphiti

public let noRootValue: Void = Void()

extension MediaType {
    public static var html: MediaType {
        return MediaType(type: "text", subtype: "html", parameters: ["charset": "utf-8"])
    }
}

struct GraphQLResponder<Root> : Responder {
    let schema: Schema<Root>
    let graphiql: Bool
    let rootValue: Root
    let contextValue: Any?

    init(
        schema: Schema<Root>,
        graphiql: Bool = false,
        rootValue: Root,
        contextValue: Any? = nil
    ) {
        self.schema = schema
        self.graphiql = graphiql
        self.rootValue = rootValue
        self.contextValue = contextValue
    }

    func respond(to request: Request) throws -> Response {
        var query: String? = nil
        var variables: [String: GraphQL.Map]? = nil
        var operationName: String? = nil
        var raw: Bool? = nil

        loop: for queryItem in request.url.queryItems {
            switch queryItem.name {
            case "query":
                query = queryItem.value
            case "variables":
                // TODO: parse variables as JSON
                break
            case "operationName":
                operationName = queryItem.value
            case "raw":
                raw = queryItem.value.flatMap({ Bool($0) })
            default:
                continue loop
            }
        }

        // Get data from ContentNegotiationMiddleware

        if query == nil {
            query = request.content?["query"].string
        }

        if variables == nil {
            if let vars = request.content?["variables"].dictionary {
                var newVariables: [String: GraphQL.Map] = [:]

                for (key, value) in vars {
                    newVariables[key] = convert(map: value)
                }

                variables = newVariables
            }
        }

        if operationName == nil {
            operationName = request.content?["operationName"].string
        }

        if raw == nil {
            raw = request.content?["raw"].bool
        }

        // TODO: Parse the body from Content-Type

        let showGraphiql = graphiql && !(raw ?? false)

        if !showGraphiql {
            guard let graphQLQuery = query else {
                throw HTTPError.badRequest(body: "Must provide query string.")
            }

            let result = try schema.execute(
                request: graphQLQuery,
                rootValue: rootValue,
                contextValue: contextValue ?? request,
                variableValues: variables ?? [:],
                operationName: operationName
            )

            return Response(content: convert(map: result))
        } else {
            var result: GraphQL.Map? = nil

            if let graphQLQuery = query {
                result = try schema.execute(
                    request: graphQLQuery,
                    rootValue: rootValue,
                    contextValue: contextValue ?? request,
                    variableValues: variables ?? [:],
                    operationName: operationName
                )
            }

            let html = renderGraphiQL(
                query: query,
                variables: variables,
                operationName: operationName,
                result: result
            )

            // TODO: Add an initializer that takes body and contentType to HTTP
            var response = Response(body: html)
            response.contentType = .html
            return response
        }
    }
}

func convert(map: Axis.Map) -> GraphQL.Map {
    switch map {
    case .null:
        return .null
    case .bool(let bool):
        return .bool(bool)
    case .double(let double):
        return .double(double)
    case .int(let int):
        return .int(int)
    case .string(let string):
        return .string(string)
    case .array(let array):
        return .array(array.map({ convert(map: $0) }))
    case .dictionary(let dictionary):
        var dict: [String: GraphQL.Map] = [:]

        for (key, value) in dictionary {
            dict[key] = convert(map: value)
        }

        return .dictionary(dict)
    default:
        return .null
    }
}

func convert(map: GraphQL.Map) -> Axis.Map {
    switch map {
    case .null:
        return .null
    case .bool(let bool):
        return .bool(bool)
    case .double(let double):
        return .double(double)
    case .int(let int):
        return .int(int)
    case .string(let string):
        return .string(string)
    case .array(let array):
        return .array(array.map({ convert(map: $0) }))
    case .dictionary(let dictionary):
        var dict: [String: Axis.Map] = [:]

        for (key, value) in dictionary {
            dict[key] = convert(map: value)
        }

        return .dictionary(dict)
    }
}
