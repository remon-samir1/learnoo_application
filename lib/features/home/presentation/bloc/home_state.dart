import 'package:equatable/equatable.dart';
import '../../../course_content/data/models/live_room.dart';

class HomeState extends Equatable {
  final bool isLoading;
  final bool isContinueWatchingLoading;
  final bool isCoursesLoading;
  final bool isSubjectsLoading;
  final bool isNotesLoading;
  final bool isLibrariesLoading;
  final bool isLiveClassesLoading;
  final String userName;
  final String universityName;
  final String facultyName;
  final String? userImageUrl;
  final List<String> centers;
  final String? userUniversityId;
  final String? userFacultyId;
  final List<String> userCenterIds;
  final List<dynamic> allCenters;
  final List<dynamic> allFaculties;
  final List<dynamic> allDepartments;
  final List<dynamic> courses;
  final List<dynamic> subjects;
  final List<dynamic> notes;
  final List<dynamic> libraries;
  final List<dynamic> continueWatchingList;
  final List<LiveRoom> liveClasses;
  final bool isSearching;
  final List<dynamic> searchResults;
  final Map<String, dynamic> searchMeta;
  final String? errorMessage;

  const HomeState({
    this.isLoading = true,
    this.isContinueWatchingLoading = true,
    this.isCoursesLoading = true,
    this.isSubjectsLoading = true,
    this.isNotesLoading = true,
    this.isLibrariesLoading = true,
    this.isLiveClassesLoading = true,
    this.userName = 'Loading...',
    this.universityName = 'Loading...',
    this.facultyName = 'Loading...',
    this.userImageUrl,
    this.centers = const [],
    this.userUniversityId,
    this.userFacultyId,
    this.userCenterIds = const [],
    this.allCenters = const [],
    this.allFaculties = const [],
    this.allDepartments = const [],
    this.courses = const [],
    this.subjects = const [],
    this.notes = const [],
    this.libraries = const [],
    this.continueWatchingList = const [],
    this.liveClasses = const [],
    this.isSearching = false,
    this.searchResults = const [],
    this.searchMeta = const {},
    this.errorMessage,
  });

  HomeState copyWith({
    bool? isLoading,
    bool? isContinueWatchingLoading,
    bool? isCoursesLoading,
    bool? isSubjectsLoading,
    bool? isNotesLoading,
    bool? isLibrariesLoading,
    bool? isLiveClassesLoading,
    String? userName,
    String? universityName,
    String? facultyName,
    String? userImageUrl,
    List<String>? centers,
    String? userUniversityId,
    String? userFacultyId,
    List<String>? userCenterIds,
    List<dynamic>? allCenters,
    List<dynamic>? allFaculties,
    List<dynamic>? allDepartments,
    List<dynamic>? courses,
    List<dynamic>? subjects,
    List<dynamic>? notes,
    List<dynamic>? libraries,
    List<dynamic>? continueWatchingList,
    List<LiveRoom>? liveClasses,
    bool? isSearching,
    List<dynamic>? searchResults,
    Map<String, dynamic>? searchMeta,
    String? errorMessage,
  }) {
    return HomeState(
      isLoading: isLoading ?? this.isLoading,
      isContinueWatchingLoading: isContinueWatchingLoading ?? this.isContinueWatchingLoading,
      isCoursesLoading: isCoursesLoading ?? this.isCoursesLoading,
      isSubjectsLoading: isSubjectsLoading ?? this.isSubjectsLoading,
      isNotesLoading: isNotesLoading ?? this.isNotesLoading,
      isLibrariesLoading: isLibrariesLoading ?? this.isLibrariesLoading,
      isLiveClassesLoading: isLiveClassesLoading ?? this.isLiveClassesLoading,
      userName: userName ?? this.userName,
      universityName: universityName ?? this.universityName,
      facultyName: facultyName ?? this.facultyName,
      userImageUrl: userImageUrl ?? this.userImageUrl,
      centers: centers ?? this.centers,
      userUniversityId: userUniversityId ?? this.userUniversityId,
      userFacultyId: userFacultyId ?? this.userFacultyId,
      userCenterIds: userCenterIds ?? this.userCenterIds,
      allCenters: allCenters ?? this.allCenters,
      allFaculties: allFaculties ?? this.allFaculties,
      allDepartments: allDepartments ?? this.allDepartments,
      courses: courses ?? this.courses,
      subjects: subjects ?? this.subjects,
      notes: notes ?? this.notes,
      libraries: libraries ?? this.libraries,
      continueWatchingList: continueWatchingList ?? this.continueWatchingList,
      liveClasses: liveClasses ?? this.liveClasses,
      isSearching: isSearching ?? this.isSearching,
      searchResults: searchResults ?? this.searchResults,
      searchMeta: searchMeta ?? this.searchMeta,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        isContinueWatchingLoading,
        isCoursesLoading,
        isSubjectsLoading,
        isNotesLoading,
        isLibrariesLoading,
        isLiveClassesLoading,
        userName,
        universityName,
        facultyName,
        userImageUrl,
        centers,
        userUniversityId,
        userFacultyId,
        userCenterIds,
        allCenters,
        allFaculties,
        allDepartments,
        courses,
        subjects,
        notes,
        libraries,
        continueWatchingList,
        liveClasses,
        isSearching,
        searchResults,
        searchMeta,
        errorMessage,
      ];
}
