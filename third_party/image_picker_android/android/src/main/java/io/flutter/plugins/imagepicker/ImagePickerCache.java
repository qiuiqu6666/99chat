// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.imagepicker;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONException;

class ImagePickerCache {
  public enum CacheType {
    IMAGE,
    VIDEO
  }

  static final String MAP_KEY_PATH_LIST = "pathList";
  static final String MAP_KEY_MAX_WIDTH = "maxWidth";
  static final String MAP_KEY_MAX_HEIGHT = "maxHeight";
  static final String MAP_KEY_IMAGE_QUALITY = "imageQuality";
  static final String MAP_KEY_TYPE = "type";
  static final String MAP_KEY_ERROR = "error";

  private static final String MAP_TYPE_VALUE_IMAGE = "image";
  private static final String MAP_TYPE_VALUE_VIDEO = "video";

  private static final String FLUTTER_IMAGE_PICKER_IMAGE_PATH_KEY =
      "flutter_image_picker_image_path";
  private static final String SHARED_PREFERENCE_ERROR_CODE_KEY = "flutter_image_picker_error_code";
  private static final String SHARED_PREFERENCE_ERROR_MESSAGE_KEY =
      "flutter_image_picker_error_message";

  private static final String SHARED_PREFERENCE_MAX_WIDTH_KEY = "flutter_image_picker_max_width";

  private static final String SHARED_PREFERENCE_MAX_HEIGHT_KEY = "flutter_image_picker_max_height";

  private static final String SHARED_PREFERENCE_IMAGE_QUALITY_KEY =
      "flutter_image_picker_image_quality";

  private static final String SHARED_PREFERENCE_TYPE_KEY = "flutter_image_picker_type";
  private static final String SHARED_PREFERENCE_PENDING_IMAGE_URI_PATH_KEY =
      "flutter_image_picker_pending_image_uri";

  @VisibleForTesting
  static final String SHARED_PREFERENCES_NAME = "flutter_image_picker_shared_preference";

  private final @NonNull Context context;

  ImagePickerCache(final @NonNull Context context) {
    this.context = context;
  }

  void saveType(CacheType type) {
    switch (type) {
      case IMAGE:
        setType(MAP_TYPE_VALUE_IMAGE);
        break;
      case VIDEO:
        setType(MAP_TYPE_VALUE_VIDEO);
        break;
    }
  }

  private void setType(String type) {
    final SharedPreferences prefs =
        context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    prefs.edit().putString(SHARED_PREFERENCE_TYPE_KEY, type).apply();
  }

  void saveDimensionWithOutputOptions(ImageSelectionOptions options) {
    final SharedPreferences prefs =
        context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    SharedPreferences.Editor editor = prefs.edit();
    if (options.getMaxWidth() != null) {
      editor.putLong(
          SHARED_PREFERENCE_MAX_WIDTH_KEY, Double.doubleToRawLongBits(options.getMaxWidth()));
    }
    if (options.getMaxHeight() != null) {
      editor.putLong(
          SHARED_PREFERENCE_MAX_HEIGHT_KEY, Double.doubleToRawLongBits(options.getMaxHeight()));
    }
    editor.putInt(SHARED_PREFERENCE_IMAGE_QUALITY_KEY, (int) options.getQuality());
    editor.apply();
  }

  void savePendingCameraMediaUriPath(Uri uri) {
    final SharedPreferences prefs =
        context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    prefs.edit().putString(SHARED_PREFERENCE_PENDING_IMAGE_URI_PATH_KEY, uri.getPath()).apply();
  }

  String retrievePendingCameraMediaUriPath() {
    final SharedPreferences prefs =
        context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    return prefs.getString(SHARED_PREFERENCE_PENDING_IMAGE_URI_PATH_KEY, "");
  }

  private static final Object RECOVERY_LOCK = new Object();
  private static final String ORDERED_PATHS = "chat_ordered_paths";
  private static final String RESULT_TOKEN = "chat_result_token";
  private static final String RESULT_OPERATION = "chat_result_operation";
  private SharedPreferences tracking() {
    return context.getSharedPreferences(SHARED_PREFERENCES_NAME + "_recovery", Context.MODE_PRIVATE);
  }
  boolean isRecoveryTracked() { return tracking().contains("operation"); }
  boolean beginRecovery(String operation) {
    return tracking().edit().putString("operation", operation).commit();
  }
  boolean endRecovery(String operation) {
    if (!operation.equals(tracking().getString("operation", null))) return false;
    return tracking().edit().clear().commit();
  }
  // Non-destructive recovery. Dart must copy files and persist its draft before ack.
  Map<String, Object> peekRecovery() {
    synchronized (RECOVERY_LOCK) {
    Map<String, Object> cached = getCacheMap();
    if (cached.isEmpty()) return cached;
    SharedPreferences prefs = context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    String token = prefs.getString(RESULT_TOKEN, null);
    if (token == null) {
      token = UUID.randomUUID().toString();
      if (!prefs.edit().putString(RESULT_TOKEN, token).commit()) throw new IllegalStateException("Cannot persist recovery token");
    }
    Map<String, Object> result = new HashMap<>();
    result.put("token", token);
    result.put("operationId", prefs.getString(RESULT_OPERATION, null));
    result.put("paths", cached.get(MAP_KEY_PATH_LIST));
    result.put("type", cached.get(MAP_KEY_TYPE) == CacheRetrievalType.VIDEO ? "video" : "image");
    result.put("errorCode", prefs.getString(SHARED_PREFERENCE_ERROR_CODE_KEY, null));
    result.put("errorMessage", prefs.getString(SHARED_PREFERENCE_ERROR_MESSAGE_KEY, null));
    return result;
      }
  }
  boolean acknowledgeRecovery(String token) {
    synchronized (RECOVERY_LOCK) {
    SharedPreferences prefs = context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    if (!token.equals(prefs.getString(RESULT_TOKEN, null))) return false;
    String operation = prefs.getString(RESULT_OPERATION, null);
    if (!prefs.edit().clear().commit()) return false;
    if (operation != null) endRecovery(operation);
    return true;
      }
  }

  boolean saveResult(
      @Nullable ArrayList<String> path, @Nullable String errorCode, @Nullable String errorMessage) {
    synchronized (RECOVERY_LOCK) {
    final SharedPreferences prefs =
        context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);

    SharedPreferences.Editor editor = prefs.edit();
    if (path != null) {
      Set<String> imageSet = new HashSet<>(path);
      editor.putStringSet(FLUTTER_IMAGE_PICKER_IMAGE_PATH_KEY, imageSet);
      editor.putString(ORDERED_PATHS, new JSONArray(path).toString());
    }
    if (errorCode != null) {
      editor.putString(SHARED_PREFERENCE_ERROR_CODE_KEY, errorCode);
    }
    if (errorMessage != null) {
      editor.putString(SHARED_PREFERENCE_ERROR_MESSAGE_KEY, errorMessage);
    }
    editor.putString(RESULT_TOKEN, UUID.randomUUID().toString());
    editor.putString(RESULT_OPERATION, tracking().getString("operation", null));
    // A result must survive another process death before the channel callback.
    return editor.commit();
      }
  }

  void clear() {
    synchronized (RECOVERY_LOCK) {
    final SharedPreferences prefs =
        context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    prefs.edit().clear().apply();
      }
  }

  Map<String, Object> getCacheMap() {
    Map<String, Object> resultMap = new HashMap<>();
    boolean hasData = false;

    final SharedPreferences prefs =
        context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);

    if (prefs.contains(ORDERED_PATHS)) {
      try {
        JSONArray paths = new JSONArray(prefs.getString(ORDERED_PATHS, "[]"));
        ArrayList<String> ordered = new ArrayList<>();
        for (int i = 0; i < paths.length(); i++) ordered.add(paths.getString(i));
        resultMap.put(MAP_KEY_PATH_LIST, ordered);
        hasData = true;
      } catch (JSONException error) {
        throw new IllegalStateException("Invalid saved picker paths", error);
      }
    } else if (prefs.contains(FLUTTER_IMAGE_PICKER_IMAGE_PATH_KEY)) {
      final Set<String> imagePathList =
          prefs.getStringSet(FLUTTER_IMAGE_PICKER_IMAGE_PATH_KEY, null);
      if (imagePathList != null) {
        ArrayList<String> pathList = new ArrayList<>(imagePathList);
        resultMap.put(MAP_KEY_PATH_LIST, pathList);
        hasData = true;
      }
    }

    if (prefs.contains(SHARED_PREFERENCE_ERROR_CODE_KEY)) {
      final CacheRetrievalError error =
          new CacheRetrievalError(
              prefs.getString(SHARED_PREFERENCE_ERROR_CODE_KEY, ""),
              prefs.getString(SHARED_PREFERENCE_ERROR_MESSAGE_KEY, null));
      hasData = true;
      resultMap.put(MAP_KEY_ERROR, error);
    }

    if (hasData) {
      if (prefs.contains(SHARED_PREFERENCE_TYPE_KEY)) {
        final String typeValue = prefs.getString(SHARED_PREFERENCE_TYPE_KEY, "");
        resultMap.put(
            MAP_KEY_TYPE,
            typeValue.equals(MAP_TYPE_VALUE_VIDEO)
                ? CacheRetrievalType.VIDEO
                : CacheRetrievalType.IMAGE);
      }
      if (prefs.contains(SHARED_PREFERENCE_MAX_WIDTH_KEY)) {
        final long maxWidthValue = prefs.getLong(SHARED_PREFERENCE_MAX_WIDTH_KEY, 0);
        resultMap.put(MAP_KEY_MAX_WIDTH, Double.longBitsToDouble(maxWidthValue));
      }
      if (prefs.contains(SHARED_PREFERENCE_MAX_HEIGHT_KEY)) {
        final long maxHeightValue = prefs.getLong(SHARED_PREFERENCE_MAX_HEIGHT_KEY, 0);
        resultMap.put(MAP_KEY_MAX_HEIGHT, Double.longBitsToDouble(maxHeightValue));
      }
      final int imageQuality = prefs.getInt(SHARED_PREFERENCE_IMAGE_QUALITY_KEY, 100);
      resultMap.put(MAP_KEY_IMAGE_QUALITY, imageQuality);
    }
    return resultMap;
  }
}
