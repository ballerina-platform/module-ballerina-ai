package io.ballerina.stdlib.ai;

import dev.langchain4j.data.document.Document;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

class MarkdownChunker {

    static Object chunkMarkdownDocumentInner(Document document, int chunkSize, int maxOverlapSize,
                                             ChunkStrategy strategy) {
        assert chunkSize > 0 : "chunkSize should be greater than 0";
        assert maxOverlapSize >= 0 : "maxOverlapSize should be greater than or equal to 0";
        assert chunkSize > maxOverlapSize;
        return null;
    }

    static List<String> chunk(String content, int chunkSize, int maxOverlapSize) {
        return chunkUsingDelimiters(content, List.of("#{2,6} .*\n", "\n\n", "\n", " ", ""), chunkSize, maxOverlapSize);
    }

    static List<String> chunkUsingDelimiters(String content, List<String> delimiters, int maxChunkSize,
            int maxOverlapSize) {
        String delimiter = delimiters.getFirst();
        List<String> rest = delimiters.subList(1, delimiters.size());
        Iterator<String> pieces = pieces(content, delimiter);
        List<String> chunks = new ArrayList<>();
        List<String> nextChunkPieceBuffer = new ArrayList<>();
        int nextChunkSize = 0;
        while (pieces.hasNext()) {
            String piece = pieces.next();
            if (nextChunkSize + piece.length() <= maxChunkSize) {
                nextChunkPieceBuffer.add(piece);
                nextChunkSize += piece.length();
                continue;
            }

            // Flush the piece buffer
            chunks.add(String.join("", nextChunkPieceBuffer));
            var lastPiece = nextChunkPieceBuffer.isEmpty() ? "" : nextChunkPieceBuffer.getLast();
            nextChunkPieceBuffer.clear();
            nextChunkSize = 0;

            // get the overlap part
            if (maxOverlapSize != 0) {
                if (lastPiece.length() < maxOverlapSize) {
                    piece = lastPiece + piece;
                } else {
                    // Break the last piece to small chunks
                    var lastPieceChunks = chunkUsingDelimiters(lastPiece, rest, maxOverlapSize, 0);
                    piece = lastPieceChunks.getLast() + piece;
                }
            }

            // If the piece is smaller than the max chunk size, just add it to the next chunk
            if (piece.length() <= maxChunkSize) {
                nextChunkPieceBuffer.add(piece);
                nextChunkSize += piece.length();
                continue;
            }

            // Break up the current piece
            var pieceChunks = chunkUsingDelimiters(piece, rest, maxChunkSize, maxOverlapSize);
            chunks.addAll(pieceChunks.subList(0, pieceChunks.size() - 1));
            String lastPieceChunk = pieceChunks.getLast();
            nextChunkPieceBuffer.add(lastPieceChunk);
            nextChunkSize += lastPieceChunk.length();
        }
        if (!nextChunkPieceBuffer.isEmpty()) {
            // Flush the last piece buffer
            chunks.add(String.join("", nextChunkPieceBuffer));
        }
        return chunks;
    }

    // TODO: do better
    static Iterator<String> pieces(String content, String delimiter) {
        List<String> pieces = new ArrayList<>();
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile(delimiter);
        java.util.regex.Matcher matcher = pattern.matcher(content);
        int lastIndex = 0;

        while (matcher.find()) {
            int delimiterStart = matcher.start();
            int delimiterEnd = matcher.end();

            // Add the content before the delimiter (if any)
            if (delimiterStart > lastIndex) {
                pieces.add(content.substring(lastIndex, delimiterStart));
            }
            // Add the delimiter itself
            pieces.add(content.substring(delimiterStart, delimiterEnd));
            lastIndex = delimiterEnd;
        }

        // Add any remaining content after the last delimiter
        if (lastIndex < content.length()) {
            pieces.add(content.substring(lastIndex));
        }

        return pieces.iterator();
    }

}
