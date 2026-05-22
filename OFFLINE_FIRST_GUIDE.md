# Offline-First Implementation Guide

## Overview

This document describes the offline-first system implemented in the Learnoo application. The system provides:

- **API Caching**: Courses, chapters, lessons, and discussions are cached locally
- **Offline Viewing**: Previously loaded data is available without internet
- **Queue System**: User actions (comments, progress) are queued when offline
- **Background Sync**: Pending actions sync automatically when connection is restored
- **Optimistic UI**: Actions appear instantly in UI while syncing in background

---

## Architecture

### 1. Repository Layer (Single Source of Truth)

Repositories combine API calls with local caching:

```dart
// GET request with offline-first support
final result = await courseRepository.getCourses();

// Response includes metadata:
// - result['fromCache']: true if data came from local storage
// - result['offline']: true if device was offline
// - result['cacheExpired']: true if cache is stale
```

**Updated Repositories:**
- `CourseRepository` - @ `lib/features/course_content/data/course_repository.dart`
- `ChapterRepository` - @ `lib/features/course_content/data/chapter_repository.dart`
- `LectureRepository` - @ `lib/features/course_content/data/lecture_repository.dart`
- `DiscussionRepository` - @ `lib/features/course_content/data/discussion_repository.dart`

### 2. Local Database (Hive)

Hive is used for fast, lightweight local storage.

**Boxes:**
- `courses` - Cached course data
- `chapters` - Cached chapter data
- `lectures` - Cached lecture data
- `comments` - Cached discussions
- `pending_actions` - Queue for offline actions
- `progress` - User progress data

**Service:** `HiveService` @ `lib/core/local/hive_service.dart`

### 3. Offline Queue System

Stores user actions when offline, syncs when online.

**Supported Actions:**
- `comment` - Add discussion/comment
- `progress` - Mark lesson as completed
- `post` - Create community post
- `reaction` - Like/react to posts
- `delete_post` - Delete a post
- `update_post` - Edit a post

**Service:** `OfflineQueueService` @ `lib/core/sync/offline_queue_service.dart`

### 4. Sync Service

Monitors connectivity and syncs pending actions.

**Features:**
- Auto-sync when connection restored
- Exponential backoff for retries (1s, 2s, 4s, 8s, 16s)
- Deduplication of identical actions
- Max 5 retry attempts per action

**Service:** `SyncService` @ `lib/core/sync/sync_service.dart`

### 5. Offline-First Repository Mixin

Provides reusable offline logic for repositories.

**Location:** `lib/core/offline/offline_first_repository.dart`

**Methods:**
- `offlineFirstFetch()` - Fetch with cache fallback
- `queueAction()` - Queue actions for offline support
- `getCached()` / `getAllCached()` - Access cached data
- `markPending()` / `unmarkPending()` - Optimistic UI helpers

---

## Integration Points

### Main.dart Initialization

Services are initialized in `main.dart`:

```dart
// Initialize Hive local database
final hiveService = HiveService();
await hiveService.initialize();

// Initialize sync service
final syncService = SyncService();
await syncService.initialize();

// Register sync processors
SyncProcessors.registerAll(syncService);
```

### Using in UI (BLoC/Provider/StatefulWidget)

#### Example: Fetching Courses

```dart
class CourseBloc {
  final CourseRepository _repository = CourseRepository();

  Future<void> loadCourses() async {
    final result = await _repository.getCourses();

    if (result['success']) {
      final courses = result['data'];
      final fromCache = result['fromCache'] ?? false;
      final isOffline = result['offline'] ?? false;

      // Show cached indicator in UI if needed
      if (fromCache) {
        showSnackbar('Showing cached data');
      }

      emit(CoursesLoaded(courses, isOffline: isOffline));
    } else {
      emit(CoursesError(result['message']));
    }
  }
}
```

#### Example: Posting Comment with Optimistic UI

```dart
class DiscussionBloc {
  final DiscussionRepository _repository = DiscussionRepository();

  Future<void> postComment({
    required int chapterId,
    required String content,
  }) async {
    // Optimistic: Add to UI immediately
    final optimisticComment = {
      'id': 'pending_${DateTime.now().millisecondsSinceEpoch}',
      'chapter_id': chapterId,
      'content': content,
      'is_pending': true,
      'created_at': DateTime.now().toIso8601String(),
    };

    emit(CommentAdded(optimisticComment, isPending: true));

    // Try to post
    final result = await _repository.postDiscussion(
      chapterId: chapterId,
      type: 'text',
      content: content,
      moment: 0,
    );

    if (result['success']) {
      if (result['queued']) {
        // Will sync when online
        showSnackbar(result['message']); // "Comment queued..."
      } else {
        // Posted successfully
        emit(CommentConfirmed(optimisticComment['id'], result['data']));
      }
    } else {
      // Remove optimistic comment on failure
      emit(CommentFailed(optimisticComment['id'], result['message']));
    }
  }
}
```

#### Example: Listening to Sync Status

```dart
class SyncIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SyncService(),
      builder: (context, _) {
        final syncService = SyncService();

        if (syncService.isSyncing) {
          return LinearProgressIndicator();
        }

        if (syncService.pendingCount > 0) {
          return Badge(
            label: Text('${syncService.pendingCount} pending'),
            child: Icon(Icons.sync),
          );
        }

        return Icon(Icons.cloud_done);
      },
    );
  }
}
```

---

## Key Features

### Exponential Backoff Retry

Failed actions retry with increasing delays:
- 1st retry: 1 second
- 2nd retry: 2 seconds
- 3rd retry: 4 seconds
- 4th retry: 8 seconds
- 5th retry: 16 seconds

After 5 retries, the action is removed from the queue.

### Deduplication

Identical actions are automatically deduplicated:
- Progress updates: Only latest per chapter is kept
- Comments: Same content + context = duplicate
- Reactions: Same post + type = duplicate

### Cache Expiration

Default cache durations:
- Courses: 24 hours
- Chapters: 24 hours
- Lectures: 24 hours
- Discussions: 30 minutes (refresh more often)
- Progress: 1 hour (changes frequently)

---

## Edge Cases Handled

1. **Duplicate Actions**: Deduplication prevents spam when user taps multiple times
2. **App Closed Before Sync**: Pending actions persist in Hive and sync on next launch
3. **Data Consistency**: API data always takes precedence over cache when online
4. **Failed Sync Retries**: Exponential backoff prevents overwhelming the API
5. **Voice Comments**: Require online connection (files can't be queued easily)
6. **Cache Expiration**: Stale data is flagged but still shown when offline

---

## Adding New Offline Actions

To add a new action type (e.g., "bookmark"):

### 1. Add Action Type Constant

```dart
// lib/core/local/models/pending_action.dart
class PendingActionTypes {
  static const String bookmark = 'bookmark';
  // ... existing types
}
```

### 2. Create Processor

```dart
// lib/core/sync/sync_processors.dart
static Future<bool> _processBookmark(PendingAction action) async {
  final token = await _getToken();
  if (token == null) return false;

  final url = Uri.parse('${ApiConstants.baseUrl}/bookmarks');

  try {
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(action.payload),
    );

    return response.statusCode == 200 || response.statusCode == 201;
  } catch (e) {
    throw Exception('Failed to bookmark: $e');
  }
}
```

### 3. Register Processor

```dart
// In SyncProcessors.registerAll()
syncService.registerProcessor(PendingActionTypes.bookmark, _processBookmark);
```

### 4. Use in Repository

```dart
// In your repository
Future<void> addBookmark(int itemId) async {
  final hasConnection = await ConnectivityService().hasConnection();

  if (!hasConnection) {
    await _queue.enqueue(
      type: PendingActionTypes.bookmark,
      payload: {'item_id': itemId},
    );
    return;
  }

  // Online - post immediately
}
```

---

## Files Modified/Created

### Core Infrastructure (Already Existed)
- `lib/core/local/hive_boxes.dart` - Box name constants
- `lib/core/local/hive_service.dart` - Database operations
- `lib/core/local/models/pending_action.dart` - Action model
- `lib/core/sync/offline_queue_service.dart` - Queue management
- `lib/core/sync/sync_service.dart` - Background sync
- `lib/core/sync/sync_processors.dart` - Action processors
- `lib/core/offline/offline_first_repository.dart` - Repository mixin
- `lib/core/services/connectivity_service.dart` - Connection detection

### Updated for Integration
- `lib/features/course_content/data/course_repository.dart` - Added offline-first
- `lib/features/course_content/data/discussion_repository.dart` - Added offline queue
- `lib/main.dart` - Added service initialization

---

## Testing Checklist

- [ ] Open courses while online (should cache)
- [ ] Open courses while offline (should show cached)
- [ ] Post comment while online (should post immediately)
- [ ] Post comment while offline (should queue)
- [ ] Restore connection (should auto-sync pending)
- [ ] Close app with pending actions (should persist)
- [ ] Reopen app offline (should show cached data)
- [ ] Reopen app online (should sync pending)

---

## Troubleshooting

### Pending actions not syncing
1. Check `SyncService().isOnline` returns true
2. Verify `SyncProcessors.registerAll()` was called
3. Check logs for processor errors

### Cache not working
1. Verify `HiveService.initialize()` completed
2. Check `result['fromCache']` in repository response
3. Ensure `maxCacheAge` hasn't expired

### Duplicates appearing
1. Call `OfflineQueueService().deduplicate()` manually
2. Check deduplication key in `_createDedupKey()`

---

## Summary

The offline-first system is now fully integrated. All GET requests are cached, all POST/PUT/DELETE actions can be queued, and sync happens automatically when online.

**Key Integration Points:**
1. Repositories use `OfflineFirstRepository` mixin
2. UI checks `result['fromCache']` and `result['queued']` for status indicators
3. `SyncService()` notifies listeners for sync status updates
4. Services initialized in `main.dart` before app launch
