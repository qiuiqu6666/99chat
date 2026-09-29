package io.flutter.plugins.imagepicker;

import static org.junit.Assert.*;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Map;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class PickerRecoveryCacheTest {
  private Context context;
  private ImagePickerCache cache;
  @Before public void setUp() {
    context = ApplicationProvider.getApplicationContext();
    context.getSharedPreferences(ImagePickerCache.SHARED_PREFERENCES_NAME, 0).edit().clear().commit();
    context.getSharedPreferences(ImagePickerCache.SHARED_PREFERENCES_NAME + "_recovery", 0).edit().clear().commit();
    cache = new ImagePickerCache(context);
  }
  @Test public void peekSurvivesRecreationAndPreservesSelectionOrder() {
    assertTrue(cache.beginRecovery("operation-a"));
    cache.clear(); // normal native picker startup must preserve tracking
    cache.saveResult(new ArrayList<>(Arrays.asList("/second.png", "/first.mov")), null, null);
    Map<String, Object> first = cache.peekRecovery();
    Map<String, Object> again = new ImagePickerCache(context).peekRecovery();
    assertEquals("operation-a", first.get("operationId"));
    assertEquals(Arrays.asList("/second.png", "/first.mov"), first.get("paths"));
    assertEquals(first, again);
    assertFalse(cache.acknowledgeRecovery("wrong-token"));
    assertEquals(first, cache.peekRecovery());
    assertTrue(cache.acknowledgeRecovery((String) first.get("token")));
    assertTrue(cache.peekRecovery().isEmpty());
    assertFalse(cache.isRecoveryTracked());
  }
  @Test public void staleAckCannotClearNewSelection() {
    cache.beginRecovery("first");
    cache.saveResult(new ArrayList<>(Arrays.asList("/first.png")), null, null);
    String token = (String) cache.peekRecovery().get("token");
    cache.beginRecovery("second");
    cache.saveResult(new ArrayList<>(Arrays.asList("/second.png")), null, null);
    assertFalse(cache.acknowledgeRecovery(token));
    assertEquals("second", cache.peekRecovery().get("operationId"));
  }
}
