# Change Log

This file documents all significant changes made to the Ballerina AI package across releases.

## [Un-released]

### Updated
- [Update the `chunkDocumentRecursively` function to support a union of string and Document as input](https://github.com/ballerina-platform/ballerina-library/issues/8143)

## [1.1.0] - 2025-07-22

### Added
- [Add `batchEmbed` API in `EmbeddingProvider`](https://github.com/ballerina-platform/ballerina-library/issues/8110).
- [Update the `ingest` method in `VectorKnowledgeBase` to utilize `EmbeddingProvider`'s `batchEmbed` API](https://github.com/ballerina-platform/ballerina-library/issues/8110).

## [1.0.0] - 2025-07-09

### Added

- Add Agent Functionality
- Add Abstractions and Implementations for `ModelProvider` and `EmbeddingProvider`
- Add `VectorStore` Abstractions and `InMemoryVectorStore` Implementation
- Add `KnowledgeBase` Abstraction and `VectorKnowledgeBase` Implementation
- Add Abstractions for `Retriever` and `VectorRetriever`
