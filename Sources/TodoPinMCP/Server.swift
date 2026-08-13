import Foundation

public final class MCPServer {
    public static let protocolVersion = "2025-06-18"

    private let storeURL: URL
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let tools: [ToolDefinition]

    public init(
        storeURL: URL,
        inputHandle: FileHandle = .standardInput,
        outputHandle: FileHandle = .standardOutput
    ) {
        self.storeURL = storeURL
        self.inputHandle = inputHandle
        self.outputHandle = outputHandle
        self.tools = toolDefinitions()
    }

    public func run() {
        var buffer = Data()
        while true {
            let chunk = inputHandle.availableData
            guard !chunk.isEmpty else {
                return
            }
            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let frame = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                guard !frame.isEmpty else {
                    continue
                }
                if let response = process(frame: frame) {
                    write(response)
                }
            }
        }
    }

    public func process(frame: Data) -> Data? {
        if let request = try? JSONDecoder().decode(MCPRequest.self, from: frame) {
            return responseFrame(for: request)
        }
        if let notification = try? JSONDecoder().decode(MCPNotification.self, from: frame) {
            _ = notification
            return nil
        }
        return encodeFrame(MCPErrorResponse(
            id: nil,
            code: MCPErrorCode.parseError,
            message: "解析错误"
        ))
    }

    private func responseFrame(for request: MCPRequest) -> Data {
        switch request.method {
        case "initialize":
            let result = JSONValue.object([
                "protocolVersion": .string(Self.protocolVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string("todopin"),
                    "version": .string("0.1.0")
                ])
            ])
            return encodeFrame(MCPSuccessResponse(id: request.id, result: result))
        case "ping":
            return encodeFrame(MCPSuccessResponse(id: request.id, result: .object([:])))
        case "tools/list":
            return toolsListFrame(for: request)
        case "tools/call":
            return toolsCallFrame(for: request)
        default:
            return encodeFrame(MCPErrorResponse(
                id: request.id,
                code: MCPErrorCode.methodNotFound,
                message: "未知方法: \(request.method)"
            ))
        }
    }

    private func toolsListFrame(for request: MCPRequest) -> Data {
        let toolsValue = tools.map { tool in
            JSONValue.object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema
            ])
        }
        let result = JSONValue.object(["tools": .array(toolsValue)])
        return encodeFrame(MCPSuccessResponse(id: request.id, result: result))
    }

    private func toolsCallFrame(for request: MCPRequest) -> Data {
        guard case .object(let params)? = request.params else {
            return encodeFrame(MCPErrorResponse(
                id: request.id,
                code: MCPErrorCode.invalidParams,
                message: "tools/call 参数必须是对象"
            ))
        }
        guard case .string(let name)? = params["name"] else {
            return encodeFrame(MCPErrorResponse(
                id: request.id,
                code: MCPErrorCode.invalidParams,
                message: "缺少工具名"
            ))
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return encodeFrame(MCPErrorResponse(
                id: request.id,
                code: MCPErrorCode.invalidParams,
                message: "未知工具: \(name)"
            ))
        }

        let arguments = params["arguments"] ?? .object([:])
        do {
            let payload = try tool.execute(arguments, storeURL)
            let text = compactJSONString(payload)
            let result = JSONValue.object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(text)
                    ])
                ])
            ])
            return encodeFrame(MCPSuccessResponse(id: request.id, result: result))
        } catch let error as MCPToolError {
            return toolErrorFrame(for: request, message: error.message)
        } catch {
            return toolErrorFrame(for: request, message: error.localizedDescription)
        }
    }

    private func toolErrorFrame(for request: MCPRequest, message: String) -> Data {
        let result = JSONValue.object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(message)
                ])
            ]),
            "isError": .bool(true)
        ])
        return encodeFrame(MCPSuccessResponse(id: request.id, result: result))
    }

    private func compactJSONString(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func encodeFrame<T: Encodable>(_ value: T) -> Data {
        do {
            return try MCPFrame.encode(value)
        } catch {
            return (try? MCPFrame.encode(
                MCPErrorResponse(
                    id: nil,
                    code: MCPErrorCode.internalError,
                    message: "响应编码失败"
                )
            )) ?? Data()
        }
    }

    private func write(_ frame: Data) {
        do {
            try outputHandle.write(contentsOf: frame)
        } catch {
            FileHandle.standardError.write(Data(("MCP 输出失败: \(error)\n").utf8))
        }
    }
}
