#!/usr/bin/env node
"use strict";
/**
 * This is a template MCP server that implements a simple notes system.
 * It demonstrates core MCP concepts like resources and tools by allowing:
 * - Listing notes as resources
 * - Reading individual notes
 * - Creating new notes via a tool
 * - Summarizing all notes via a prompt
 */
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
var __spreadArray = (this && this.__spreadArray) || function (to, from, pack) {
    if (pack || arguments.length === 2) for (var i = 0, l = from.length, ar; i < l; i++) {
        if (ar || !(i in from)) {
            if (!ar) ar = Array.prototype.slice.call(from, 0, i);
            ar[i] = from[i];
        }
    }
    return to.concat(ar || Array.prototype.slice.call(from));
};
exports.__esModule = true;
var index_js_1 = require("@modelcontextprotocol/sdk/server/index.js");
var stdio_js_1 = require("@modelcontextprotocol/sdk/server/stdio.js");
var types_js_1 = require("@modelcontextprotocol/sdk/types.js");
/**
 * Database connection setup for SQL Server.
 */
var sql = require("mssql");
var config = {
    user: "UIAdmin",
    password: "hk099wjuYT7!",
    server: "cofdev.database.windows.net",
    database: "Cof",
    options: {
        encrypt: true,
        trustServerCertificate: false
    }
};
function queryDatabase(query) {
    return __awaiter(this, void 0, void 0, function () {
        var pool, result, err_1;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    _a.trys.push([0, 3, , 4]);
                    return [4 /*yield*/, sql.connect(config)];
                case 1:
                    pool = _a.sent();
                    return [4 /*yield*/, pool.request().query(query)];
                case 2:
                    result = _a.sent();
                    return [2 /*return*/, result.recordset];
                case 3:
                    err_1 = _a.sent();
                    if (err_1 instanceof Error) {
                        throw new Error("Database query failed: ".concat(err_1.message));
                    }
                    else {
                        throw new Error("Database query failed with an unknown error.");
                    }
                    return [3 /*break*/, 4];
                case 4: return [2 /*return*/];
            }
        });
    });
}
/**
 * Create an MCP server with capabilities for resources (to list/read notes),
 * tools (to create new notes), and prompts (to summarize notes).
 */
var server = new index_js_1.Server({
    name: "cof-database",
    version: "0.1.0"
}, {
    capabilities: {
        resources: {},
        tools: {},
        prompts: {}
    }
});
/**
 * Handler for listing available notes as resources.
 * Each note is exposed as a resource with:
 * - A note:// URI scheme
 * - Plain text MIME type
 * - Human readable name and description (now including the note title)
 */
server.setRequestHandler(types_js_1.ListResourcesRequestSchema, function () { return __awaiter(void 0, void 0, void 0, function () {
    return __generator(this, function (_a) {
        return [2 /*return*/, {
                resources: []
            }];
    });
}); });
/**
 * Handler for reading the contents of a specific note.
 * Takes a note:// URI and returns the note content as plain text.
 */
server.setRequestHandler(types_js_1.ReadResourceRequestSchema, function (request) { return __awaiter(void 0, void 0, void 0, function () {
    var url, id;
    return __generator(this, function (_a) {
        url = new URL(request.params.uri);
        id = url.pathname.replace(/^\//, '');
        throw new Error("Resource not found.");
    });
}); });
/**
 * Handler that lists available tools.
 * Exposes tools for querying the SQL Server database and retrieving schema information.
 */
server.setRequestHandler(types_js_1.ListToolsRequestSchema, function () { return __awaiter(void 0, void 0, void 0, function () {
    return __generator(this, function (_a) {
        return [2 /*return*/, {
                tools: [
                    {
                        name: "execute_query",
                        description: "Execute a SQL query on the database",
                        inputSchema: {
                            type: "object",
                            properties: {
                                query: {
                                    type: "string",
                                    description: "SQL query to execute"
                                }
                            },
                            required: ["query"]
                        }
                    },
                    {
                        name: "get_schema_info",
                        description: "Retrieve database schema information, including tables and stored procedures",
                        inputSchema: {
                            type: "object",
                            properties: {},
                            required: []
                        }
                    },
                ]
            }];
    });
}); });
/**
 * Handler for the execute_query and get_schema_info tools.
 * Executes the provided SQL query or retrieves schema information.
 */
server.setRequestHandler(types_js_1.CallToolRequestSchema, function (request) { return __awaiter(void 0, void 0, void 0, function () {
    var _a, query, results, schemaQuery, results;
    var _b;
    return __generator(this, function (_c) {
        switch (_c.label) {
            case 0:
                _a = request.params.name;
                switch (_a) {
                    case "execute_query": return [3 /*break*/, 1];
                    case "get_schema_info": return [3 /*break*/, 3];
                }
                return [3 /*break*/, 5];
            case 1:
                query = String((_b = request.params.arguments) === null || _b === void 0 ? void 0 : _b.query);
                if (!query) {
                    throw new Error("Query is required");
                }
                return [4 /*yield*/, queryDatabase(query)];
            case 2:
                results = _c.sent();
                return [2 /*return*/, {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify(results, null, 2)
                            },
                        ]
                    }];
            case 3:
                schemaQuery = "\n        SELECT TABLE_NAME AS TableName, TABLE_TYPE AS TableType\n        FROM INFORMATION_SCHEMA.TABLES;\n        \n        SELECT SPECIFIC_NAME AS ProcedureName\n        FROM INFORMATION_SCHEMA.ROUTINES\n        WHERE ROUTINE_TYPE = 'PROCEDURE';\n      ";
                return [4 /*yield*/, queryDatabase(schemaQuery)];
            case 4:
                results = _c.sent();
                return [2 /*return*/, {
                        content: [
                            {
                                type: "text",
                                text: JSON.stringify(results, null, 2)
                            },
                        ]
                    }];
            case 5: throw new Error("Unknown tool");
        }
    });
}); });
/**
 * Handler that lists available prompts.
 * Exposes a single "summarize_notes" prompt that summarizes all notes.
 */
server.setRequestHandler(types_js_1.ListPromptsRequestSchema, function () { return __awaiter(void 0, void 0, void 0, function () {
    return __generator(this, function (_a) {
        return [2 /*return*/, {
                prompts: [
                    {
                        name: "summarize_notes",
                        description: "Summarize all notes"
                    }
                ]
            }];
    });
}); });
/**
 * Handler for the summarize_notes prompt.
 * Returns a prompt that requests summarization of all notes, with the notes' contents embedded as resources.
 */
server.setRequestHandler(types_js_1.GetPromptRequestSchema, function (request) { return __awaiter(void 0, void 0, void 0, function () {
    var embeddedNotes;
    return __generator(this, function (_a) {
        if (request.params.name !== "summarize_notes") {
            throw new Error("Unknown prompt");
        }
        embeddedNotes = [];
        return [2 /*return*/, {
                messages: __spreadArray(__spreadArray([
                    {
                        role: "user",
                        content: {
                            type: "text",
                            text: "Please summarize the following notes:"
                        }
                    }
                ], embeddedNotes.map(function (note) { return ({
                    role: "user",
                    content: note
                }); }), true), [
                    {
                        role: "user",
                        content: {
                            type: "text",
                            text: "Provide a concise summary of all the notes above."
                        }
                    }
                ], false)
            }];
    });
}); });
/**
 * Start the server using stdio transport.
 * This allows the server to communicate via standard input/output streams.
 */
function main() {
    return __awaiter(this, void 0, void 0, function () {
        var transport;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    transport = new stdio_js_1.StdioServerTransport();
                    return [4 /*yield*/, server.connect(transport)];
                case 1:
                    _a.sent();
                    return [2 /*return*/];
            }
        });
    });
}
main()["catch"](function (error) {
    console.error("Server error:", error);
    process.exit(1);
});
