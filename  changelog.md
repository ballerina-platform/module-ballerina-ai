# Change Log

This file documents all significant changes made to the Ballerina AI package across releases.

## [Un-released]

### Added
- Add `batchEmbed` API in `EmbeddingProvider`.
- Update the `ingest` method in `VectorKnowledgeBase` to utilize `EmbeddingProvider`'s `batchEmbed` API.

## [1.0.0] - 2025-07-09

### Added

- Add Agent Functionality
- Add Abstractions and Implementations for `ModelProvider` and `EmbeddingProvider`
- Add `VectorStore` Abstractions and `InMemoryVectorStore` Implementation
- Add `KnowledgeBase` Abstraction and `VectorKnowledgeBase` Implementation
- Add Abstractions for `Retriever` and `VectorRetriever`
