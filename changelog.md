# Change Log

This file documents all significant changes made to the Ballerina AI package across releases.

## [Unreleased]

## [1.15.0] - 2026-09-09

### Added
- [Add Support for `anydata` Input in Agent](https://github.com/wso2/product-integrator/issues/2300)
- [Add `Tag` Marker Type](https://github.com/wso2/product-integrator/issues/2300)

### Changed
- **Breaking:** `Resume` (a closed record) now has an additional `tag` field to distinguish it from an `anydata` query, and is now a `readonly` record, so `decisions` must be passed as a `readonly` `map<HumanDecision>`. ([wso2/product-integrator#2300](https://github.com/wso2/product-integrator/issues/2300))
- **Breaking:** `DecisionMessage` is now a `readonly` record, so `decisions` must be passed as a `readonly` `map<HumanDecision>`. ([wso2/product-integrator#2300](https://github.com/wso2/product-integrator/issues/2300))
- **Breaking:** The human-in-the-loop decision types are renamed so that the word "decision" no longer appears twice in every read (`decisions[id].decision`). `HumanResponse` is now `HumanDecision`, the `ApprovalDecision` enum is now `ApprovalOutcome`, and the record's `decision` field is now `outcome`. The `APPROVE` and `REJECT` members are unchanged, and every `decisions` field name (`Resume`, `DecisionMessage`, `PendingApproval`) keeps its current name, so a resume now reads `{decisions: {[req.id]: {outcome: ai:APPROVE}}}`. Note that the JSON key inside each entry changes from `decision` to `outcome`: a checkpoint persisted by an external `ShortTermMemoryStore` before this release will not deserialize, so any run left paused across the upgrade must be restarted.

## [1.14.1] - 2026-08-25

### Fixed
- [Fix Empty Module `init` Function Generated for Modules That Define Only an Agent Class or an Agent Tool](https://github.com/ballerina-platform/ballerina-library/issues/9098)

## [1.14.0] - 2026-08-14

### Added
- [Add Agent Configuration to Execute Tool Calls in Parallel](https://github.com/wso2/product-integrator/issues/1856)
- [Add Structured Human Decision Support to Chat Service via a `decision` Resource](https://github.com/ballerina-platform/ballerina-library/issues/9006)

### Fixed
- [Fix `maxIter` Inference with Toolkits and Enforce Minimum of 10](https://github.com/wso2/product-integrator/issues/1112)
- [Fix OpenAPI Spec Defaulting to Port 9090 When an AI Agent Listener Uses an Inline `http:Listener`](https://github.com/wso2/product-integrator/issues/1676)

### Updated
- [Execute Multiple Tool Calls Returned in a Single LLM Response Together](https://github.com/wso2/product-integrator/issues/1833)

## [1.13.0] - 2026-08-03

### Added
- [Add Human-in-the-Loop Support to Pause the Agent for Approval Before Executing Sensitive Tools](https://github.com/wso2/product-integrator/issues/2006)
- [Introduce an Object Type for Agents to Support Sharable, Reusable Agent Definitions](https://github.com/ballerina-platform/ballerina-library/issues/9097)

### Updated
- **Breaking:** `ShortTermMemoryStore` now requires four checkpoint methods (`putCheckpoint`, `getCheckpoint`, `removeCheckpoint`, and `takeCheckpoint`) to support Human-in-the-Loop pauses. Existing custom `ShortTermMemoryStore` implementations must add these methods to keep conforming. ([#148](https://github.com/ballerina-platform/module-ballerina-ai/pull/148))
- **Breaking:** The `AgentType` enum (`REACT_AGENT`, `FUNCTION_CALL_AGENT`) has been replaced by the `DependentlyTypedAgent|FixedTypedAgent` object-type union, so that custom agent definitions can be subtypes of `ai:AgentType`. ([#141](https://github.com/ballerina-platform/module-ballerina-ai/pull/141))

## [1.11.1] - 2026-04-16

### Fixed
- [Fix Knowledge Base Retrieve Span Missing Input/Output tags](https://github.com/wso2/product-integrator/issues/635)

## [1.11.0] - 2026-03-27

### Added
- [Add Agent Identity](https://github.com/ballerina-platform/module-ballerina-ai/pull/126)

## [1.10.0] - 2026-03-14

### Added
- [Add `getUserQuery` Function to Obtain User Query as String from Trace Record](https://github.com/ballerina-platform/module-ballerina-ai/pull/119)
- [Add Support to Load Conversation Threads from Evaluation Dataset JSON](https://github.com/wso2/product-ballerina-integrator/issues/2399)
- [Add Tool Invocation Tracking to ai:Trace via `toolCalls` Field](https://github.com/wso2/product-ballerina-integrator/issues/2425)

## [1.9.0] - 2026-01-06

### Added
- [Add Support for Batch update in Agent Memory](https://github.com/wso2/product-ballerina-integrator/issues/2081)
- [Add `Trace` binding support to the `ai:Agent` run method](https://github.com/wso2/product-ballerina-integrator/issues/2053)

## [1.8.0] - 2025-11-14

### Added
- [Add Lazy Tool Loading to ai:Agent for Accurate LLM Tool Selection](https://github.com/wso2/product-ballerina-integrator/issues/1679)

### Updated
- [Remove Lock From Agent Run and Move Lock to Memory Implementations](https://github.com/wso2/product-ballerina-integrator/issues/1818)

### Fixed
- [Fix Improper Closure of Chat Span in Wso2ModelProvider](https://github.com/wso2/product-ballerina-integrator/issues/1835)

## [1.7.0] - 2025-11-03

### Added
- [Add Tracing to AI Componets](https://github.com/ballerina-platform/ballerina-library/issues/8341)

### Updated
- [Enhance Error Message with Additional Error Details on Tool Call Failure](https://github.com/ballerina-platform/ballerina-library/issues/8416)


### Fixed
- [Fix Tool with Default Parameter Execution Failing when `ai:Context` is Present](https://github.com/ballerina-platform/ballerina-library/issues/8418)

## [1.6.1] - 2025-10-29

### Fixed
- [Fix OpenAPI Specification Generation Failure for `ai:ChatService`](https://github.com/wso2/product-ballerina-integrator/issues/1634)

## [1.6.0] - 2025-10-23

### Added
- [Add `McpBaseToolKit` Type and `getPermittedMcpToolConfigs` Function](https://github.com/ballerina-platform/ballerina-library/issues/8328)
- [Add support for configurable short-term memory with support for persistence and overflow handling](https://github.com/ballerina-platform/ballerina-library/issues/8375)

### Fixed
- [Inherent type violation in `prev` field](https://github.com/ballerina-platform/ballerina-library/issues/8380)


## [1.5.4] - 2025-10-03
- This release upgrades the MCP dependency to the stable 1.0.0 version

## [1.5.3] - 2025-09-22

### Fixed
- [Reflect MCP Client Initialization Decoupling](https://github.com/ballerina-platform/ballerina-library/issues/8178)

## [1.5.2] - 2025-09-10

### Added
- [Add Support for Markdown and HTML in TextDataLoader](https://github.com/ballerina-platform/ballerina-library/issues/8228)

### Fixed
- [Fix TextDataLoader Sets `fileName` Metadata to File Path](https://github.com/ballerina-platform/ballerina-library/issues/8230)

## [1.5.1] - 2025-09-09

### Removed
- [Remove `commons-lang3` Dependency](https://github.com/ballerina-platform/ballerina-library/issues/8220).

## [1.5.0] - 2025-08-29

### Added
- [Add `deleteByFilter` API to KnowledgeBase](https://github.com/ballerina-platform/ballerina-library/issues/8198)

### Updated
- [Update KnowledgeBase `retrieve` Method to Accept `limit` Parameter](https://github.com/ballerina-platform/ballerina-library/issues/8204)


## [1.4.0] - 2025-08-22

### Added
- [Add HTMLChunker Implementation](https://github.com/ballerina-platform/ballerina-library/issues/8170)

### Fixed
- [Fix Model Provider Errors Not Propagated to ai:Error in Agent Run Steps](https://github.com/ballerina-platform/ballerina-library/issues/8192)

## [1.3.1] - 2025-08-18

### Updated
- [Update batchEmbed to Validate Chunks at Element Level](https://github.com/ballerina-platform/ballerina-library/issues/8171)


## [1.3.0] - 2025-08-16

### Added
- [Add Chunker Type and GenericRecursiveChunker Implementation](https://github.com/ballerina-platform/ballerina-library/issues/8166)
- [Add DataLoader Type to Enable Loading Documents from Various Data Sources](https://github.com/ballerina-platform/ballerina-library/issues/8167)
- [Add MarkdownChunker Implementation](https://github.com/ballerina-platform/ballerina-library/issues/8162)

### Updated
- [Update VectorKnowledgeBase to Accept a Chunker During Initialization](https://github.com/ballerina-platform/ballerina-library/issues/8168)

## [1.2.0] - 2025-08-15

### Added
- [Add Support for Passing Additional Context to Agents](https://github.com/ballerina-platform/ballerina-library/issues/8154)

### Updated
- [Update the `chunkDocumentRecursively` Function To support a Union of String and Document as Input](https://github.com/ballerina-platform/ballerina-library/issues/8143)

## [1.1.0] - 2025-07-22


- [Add `batchEmbed` API in `EmbeddingProvider`](https://github.com/ballerina-platform/ballerina-library/issues/8110).
- [Update the `ingest` Method in `VectorKnowledgeBase` to Utilize `EmbeddingProvider`'s `batchEmbed` API](https://github.com/ballerina-platform/ballerina-library/issues/8110).

## [1.0.0] - 2025-07-09

### Added

- Add Agent Functionality
- Add Abstractions and Implementations for `ModelProvider` and `EmbeddingProvider`
- Add `VectorStore` Abstractions and `InMemoryVectorStore` Implementation
- Add `KnowledgeBase` Abstraction and `VectorKnowledgeBase` Implementation
- Add Abstractions for `Retriever` and `VectorRetriever`
