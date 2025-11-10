# Change Log

This file documents all significant changes made to the Ballerina AI package across releases.

## [Unreleased]

## [1.7.0] - 2025-11-03

### Added
- [Add Tracing to AI Componets](https://github.com/ballerina-platform/ballerina-library/issues/8341)
- [Add Lazy Tool Loading to ai:Agent for Accurate LLM Tool Selection](https://github.com/wso2/product-ballerina-integrator/issues/1679)

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
