# Change Log

This file documents all significant changes made to the Ballerina AI package across releases.

## [Unreleased]

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
