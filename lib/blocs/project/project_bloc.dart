import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/project_service.dart';
import 'project_event.dart';
import 'project_state.dart';

class ProjectBloc extends Bloc<ProjectEvent, ProjectState> {
  final ProjectService _projectService;

  ProjectBloc({ProjectService? projectService})
      : _projectService = projectService ?? ProjectService(),
        super(const ProjectInitial()) {
    on<LoadProjects>(_onLoadProjects);
    on<AddProject>(_onAddProject);
    on<UpdateProject>(_onUpdateProject);
    on<DeleteProject>(_onDeleteProject);
  }

  Future<void> _onLoadProjects(
    LoadProjects event,
    Emitter<ProjectState> emit,
  ) async {
    emit(const ProjectLoading());
    try {
      final projects = await _projectService.listProjects();
      emit(ProjectLoaded(projects));
    } catch (e) {
      emit(ProjectError(e.toString()));
    }
  }

  Future<void> _onAddProject(
    AddProject event,
    Emitter<ProjectState> emit,
  ) async {
    try {
      await _projectService.saveProject(event.project);
      add(const LoadProjects());
    } catch (e) {
      emit(ProjectError(e.toString()));
    }
  }

  Future<void> _onUpdateProject(
    UpdateProject event,
    Emitter<ProjectState> emit,
  ) async {
    try {
      await _projectService.saveProject(event.project);
      add(const LoadProjects());
    } catch (e) {
      emit(ProjectError(e.toString()));
    }
  }

  Future<void> _onDeleteProject(
    DeleteProject event,
    Emitter<ProjectState> emit,
  ) async {
    try {
      await _projectService.deleteProject(event.projectId);
      add(const LoadProjects());
    } catch (e) {
      emit(ProjectError(e.toString()));
    }
  }
}
