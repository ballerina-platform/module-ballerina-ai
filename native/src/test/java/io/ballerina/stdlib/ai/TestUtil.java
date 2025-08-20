package io.ballerina.stdlib.ai;

import java.lang.reflect.Field;
import java.util.concurrent.atomic.AtomicLong;

public class TestUtil {

    public static void resetChunkIdCounter() throws Exception {
        Field nextIdField = RecursiveChunker.Chunk.class.getDeclaredField("nextId");
        nextIdField.setAccessible(true);
        AtomicLong nextId = (AtomicLong) nextIdField.get(null);
        nextId.set(0);
    }
}