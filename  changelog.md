# Change Log

This file documents all significant changes made to the Ballerina AI package across releases.

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
