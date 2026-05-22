import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../course_content/data/models/live_room.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../course_content/data/course_repository.dart';
import '../../../course_content/data/library_repository.dart';
import '../../../course_content/data/chapter_repository.dart';
import '../../../course_content/data/live_room_repository.dart';
import '../../../notes/data/notes_repository.dart';
import '../../data/department_repository.dart';
import '../../../search/data/search_repository.dart';
import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final AuthRepository _authRepository;
  final CourseRepository _courseRepository;
  final DepartmentRepository _departmentRepository;
  final NotesRepository _notesRepository;
  final LibraryRepository _libraryRepository;
  final ChapterRepository _chapterRepository;
  final SearchRepository _searchRepository;
  final LiveRoomRepository _liveRoomRepository;

  HomeBloc({
    required AuthRepository authRepository,
    required CourseRepository courseRepository,
    required DepartmentRepository departmentRepository,
    required NotesRepository notesRepository,
    required LibraryRepository libraryRepository,
    required ChapterRepository chapterRepository,
    required SearchRepository searchRepository,
    required LiveRoomRepository liveRoomRepository,
  })  : _authRepository = authRepository,
        _courseRepository = courseRepository,
        _departmentRepository = departmentRepository,
        _notesRepository = notesRepository,
        _libraryRepository = libraryRepository,
        _chapterRepository = chapterRepository,
        _searchRepository = searchRepository,
        _liveRoomRepository = liveRoomRepository,
        super(const HomeState()) {
    on<LoadUserDataEvent>(_onLoadUserData);
    on<LoadCoursesEvent>(_onLoadCourses);
    on<LoadSubjectsEvent>(_onLoadSubjects);
    on<LoadNotesEvent>(_onLoadNotes);
    on<LoadLibrariesEvent>(_onLoadLibraries);
    on<LoadLiveClassesEvent>(_onLoadLiveClasses);
    on<LoadContinueWatchingEvent>(_onLoadContinueWatching);
    on<SearchEvent>(_onSearch);
    on<ClearSearchEvent>(_onClearSearch);
    on<RefreshAllEvent>(_onRefreshAll);
  }

  Future<void> _onLoadUserData(
    LoadUserDataEvent event,
    Emitter<HomeState> emit,
  ) async {
    try {
      final profileResult = await _authRepository.getProfile();
      if (profileResult['success']) {
        final attributes = profileResult['data']['attributes'];
        final firstName = (attributes['first_name'] ?? '').toString();
        final lastName = (attributes['last_name'] ?? '').toString();
        final fullName = '$firstName $lastName'.trim();

        final universityName =
            (attributes['university']?['data']?['attributes']?['name'] ??
                    'home.university_not_set')
                .toString();

        final facultyName =
            (attributes['faculty']?['data']?['attributes']?['name'] ??
                    'home.faculty_not_set')
                .toString();

        final centersData = attributes['centers'] as List<dynamic>? ?? [];
        final centers = centersData
            .map((center) {
              return (center['attributes']?['name'] ?? '').toString();
            })
            .where((name) => name.isNotEmpty)
            .toList();

        final universityId = attributes['university']?['data']?['id']?.toString();
        final facultyId = attributes['faculty']?['data']?['id']?.toString();
        final centerIds = centersData
            .map((c) => c['id']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toList();

        final userImage = attributes['image']?.toString();

        emit(state.copyWith(
          userName: fullName.isEmpty ? 'User' : fullName,
          universityName: universityName,
          facultyName: facultyName,
          userImageUrl: userImage,
          centers: centers,
          userUniversityId: universityId,
          userFacultyId: facultyId,
          userCenterIds: centerIds,
          isLoading: false,
        ));

        // Load centers and faculties for hierarchy validation
        await _loadCentersAndFaculties(emit);
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _loadCentersAndFaculties(Emitter<HomeState> emit) async {
    try {
      final centersResult = await _departmentRepository.getCenters();
      final allCenters = centersResult['success'] ? (centersResult['data'] ?? []) : [];

      final facultiesResult = await _departmentRepository.getFaculties();
      final allFaculties = facultiesResult['success'] ? (facultiesResult['data'] ?? []) : [];

      emit(state.copyWith(
        allCenters: allCenters,
        allFaculties: allFaculties,
      ));

      // Reload subjects with hierarchy filtering
      add(LoadSubjectsEvent());
      // Reload courses to filter by available departments
      add(LoadCoursesEvent());
    } catch (e) {
      // Fallback: load subjects without filtering
      add(LoadSubjectsEvent());
      add(LoadCoursesEvent());
    }
  }

  Future<void> _onLoadCourses(
    LoadCoursesEvent event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(isCoursesLoading: true));
    try {
      final result = await _courseRepository.getActivatedCourses();
      if (result['success']) {
        emit(state.copyWith(
          courses: result['data'] ?? [],
          isCoursesLoading: false,
        ));
      } else {
        emit(state.copyWith(isCoursesLoading: false));
      }
    } catch (e) {
      emit(state.copyWith(isCoursesLoading: false));
    }
  }

  Future<void> _onLoadSubjects(
    LoadSubjectsEvent event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(isSubjectsLoading: true));
    try {
      final departmentsResult = await _departmentRepository.getDepartments();
      
      if (departmentsResult['success']) {
        final allDepartments = departmentsResult['data'] ?? [];
        
        // Store unfiltered list for nested navigation
        emit(state.copyWith(allDepartments: allDepartments));
        
        // Filter departments by user's faculty
        List<dynamic> filteredSubjects = allDepartments;
        if (state.userFacultyId != null && state.userFacultyId!.isNotEmpty) {
          filteredSubjects = allDepartments.where((dept) {
            final attributes = dept['attributes'] ?? {};
            
            // Check parent_id (direct children of faculty)
            final parentId = attributes['parent_id']?.toString();
            if (parentId == state.userFacultyId) return true;
            
            // Check parent.data.id (nested parent structure)
            final parentDataId = attributes['parent']?['data']?['id']?.toString();
            if (parentDataId == state.userFacultyId) return true;
            
            return false;
          }).toList();
        }
        
        emit(state.copyWith(
          subjects: filteredSubjects,
          isSubjectsLoading: false,
        ));
      } else {
        emit(state.copyWith(isSubjectsLoading: false));
      }
    } catch (e) {
      emit(state.copyWith(isSubjectsLoading: false));
    }
  }

  Future<void> _onLoadNotes(
    LoadNotesEvent event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(isNotesLoading: true));
    try {
      final result = await _notesRepository.getNotes();
      if (result['success']) {
        emit(state.copyWith(
          notes: result['data'] ?? [],
          isNotesLoading: false,
        ));
      } else {
        emit(state.copyWith(isNotesLoading: false));
      }
    } catch (e) {
      emit(state.copyWith(isNotesLoading: false));
    }
  }

  Future<void> _onLoadLibraries(
    LoadLibrariesEvent event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(isLibrariesLoading: true));
    try {
      final result = await _libraryRepository.getLibraries();
      if (result['success']) {
        emit(state.copyWith(
          libraries: result['data'] ?? [],
          isLibrariesLoading: false,
        ));
      } else {
        emit(state.copyWith(isLibrariesLoading: false));
      }
    } catch (e) {
      emit(state.copyWith(isLibrariesLoading: false));
    }
  }

  Future<void> _onLoadLiveClasses(
    LoadLiveClassesEvent event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(isLiveClassesLoading: true));
    try {
      final result = await _liveRoomRepository.getLiveRooms();
      if (result['success']) {
        emit(state.copyWith(
          liveClasses: result['data'] as List<LiveRoom>,
          isLiveClassesLoading: false,
        ));
      } else {
        emit(state.copyWith(isLiveClassesLoading: false));
      }
    } catch (e) {
      emit(state.copyWith(isLiveClassesLoading: false));
    }
  }

  Future<void> _onLoadContinueWatching(
    LoadContinueWatchingEvent event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(isContinueWatchingLoading: true));
    try {
      final result = await _chapterRepository.getUserProgress();
      if (result['success']) {
        emit(state.copyWith(
          continueWatchingList: result['data'] ?? [],
          isContinueWatchingLoading: false,
        ));
      } else {
        emit(state.copyWith(isContinueWatchingLoading: false));
      }
    } catch (e) {
      emit(state.copyWith(isContinueWatchingLoading: false));
    }
  }

  Future<void> _onSearch(
    SearchEvent event,
    Emitter<HomeState> emit,
  ) async {
    if (event.query.isEmpty) {
      emit(state.copyWith(
        isSearching: false,
        searchResults: [],
        searchMeta: {},
      ));
      return;
    }

    emit(state.copyWith(isSearching: true));

    try {
      final result = await _searchRepository.search(
        query: event.query,
        type: null,
        limit: 10,
      );

      if (result['success']) {
        emit(state.copyWith(
          searchResults: result['data'] ?? [],
          searchMeta: result['meta'] ?? {},
          isSearching: false,
        ));
      } else {
        emit(state.copyWith(
          searchResults: [],
          searchMeta: {},
          isSearching: false,
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        searchResults: [],
        searchMeta: {},
        isSearching: false,
      ));
    }
  }

  Future<void> _onClearSearch(
    ClearSearchEvent event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(
      searchResults: [],
      searchMeta: {},
      isSearching: false,
    ));
  }

  Future<void> _onRefreshAll(
    RefreshAllEvent event,
    Emitter<HomeState> emit,
  ) async {
    // Load all data in parallel for faster refresh
    await Future.wait([
      _authRepository.getProfile().then((result) {
        if (result['success']) {
          final attributes = result['data']['attributes'];
          final firstName = (attributes['first_name'] ?? '').toString();
          final lastName = (attributes['last_name'] ?? '').toString();
          final fullName = '$firstName $lastName'.trim();

          final universityName =
              (attributes['university']?['data']?['attributes']?['name'] ??
                      'home.university_not_set')
                  .toString();

          final facultyName =
              (attributes['faculty']?['data']?['attributes']?['name'] ??
                      'home.faculty_not_set')
                  .toString();

          final centersData = attributes['centers'] as List<dynamic>? ?? [];
          final centers = centersData
              .map((center) {
                return (center['attributes']?['name'] ?? '').toString();
              })
              .where((name) => name.isNotEmpty)
              .toList();

          final universityId = attributes['university']?['data']?['id']?.toString();
          final facultyId = attributes['faculty']?['data']?['id']?.toString();
          final centerIds = centersData
              .map((c) => c['id']?.toString())
              .where((id) => id != null)
              .cast<String>()
              .toList();

          final userImage = attributes['image']?.toString();

          emit(state.copyWith(
            userName: fullName.isEmpty ? 'User' : fullName,
            universityName: universityName,
            facultyName: facultyName,
            userImageUrl: userImage,
            centers: centers,
            userUniversityId: universityId,
            userFacultyId: facultyId,
            userCenterIds: centerIds,
            isLoading: false,
          ));
        }
      }),
      _courseRepository.getActivatedCourses().then((result) {
        if (result['success']) {
          emit(state.copyWith(courses: result['data'] ?? []));
        }
      }),
      _departmentRepository.getDepartments().then((result) {
        if (result['success']) {
          final allDepartments = result['data'] ?? [];
          emit(state.copyWith(allDepartments: allDepartments));
          
          // Filter departments by user's faculty
          List<dynamic> filteredSubjects = allDepartments;
          if (state.userFacultyId != null && state.userFacultyId!.isNotEmpty) {
            filteredSubjects = allDepartments.where((dept) {
              final attributes = dept['attributes'] ?? {};
              final parentId = attributes['parent_id']?.toString();
              if (parentId == state.userFacultyId) return true;
              final parentDataId = attributes['parent']?['data']?['id']?.toString();
              if (parentDataId == state.userFacultyId) return true;
              return false;
            }).toList();
          }
          emit(state.copyWith(subjects: filteredSubjects));
        }
      }),
      _liveRoomRepository.getLiveRooms().then((result) {
        if (result['success']) {
          emit(state.copyWith(liveClasses: result['data'] as List<LiveRoom>));
        }
      }),
      _notesRepository.getNotes().then((result) {
        if (result['success']) {
          emit(state.copyWith(notes: result['data'] ?? []));
        }
      }),
      _libraryRepository.getLibraries().then((result) {
        if (result['success']) {
          emit(state.copyWith(libraries: result['data'] ?? []));
        }
      }),
      _chapterRepository.getUserProgress().then((result) {
        if (result['success']) {
          emit(state.copyWith(continueWatchingList: result['data'] ?? []));
        }
      }),
    ]);
  }
}
