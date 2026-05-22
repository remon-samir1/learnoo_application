import 'package:equatable/equatable.dart';

abstract class HomeEvent extends Equatable {
  const HomeEvent();

  @override
  List<Object?> get props => [];
}

class LoadUserDataEvent extends HomeEvent {
  const LoadUserDataEvent();
}

class LoadCoursesEvent extends HomeEvent {
  const LoadCoursesEvent();
}

class LoadSubjectsEvent extends HomeEvent {
  const LoadSubjectsEvent();
}

class LoadNotesEvent extends HomeEvent {
  const LoadNotesEvent();
}

class LoadLibrariesEvent extends HomeEvent {
  const LoadLibrariesEvent();
}

class LoadLiveClassesEvent extends HomeEvent {
  const LoadLiveClassesEvent();
}

class LoadContinueWatchingEvent extends HomeEvent {
  const LoadContinueWatchingEvent();
}

class SearchEvent extends HomeEvent {
  final String query;

  const SearchEvent(this.query);

  @override
  List<Object?> get props => [query];
}

class ClearSearchEvent extends HomeEvent {
  const ClearSearchEvent();
}

class RefreshAllEvent extends HomeEvent {
  const RefreshAllEvent();
}
