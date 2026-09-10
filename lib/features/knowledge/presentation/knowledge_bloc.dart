import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/knowledge_database.dart';
import '../domain/entities/knowledge_node.dart';

class KnowledgeListState {
  const KnowledgeListState({
    this.nodes = const [],
    this.loading = false,
    this.error,
  });

  final List<KnowledgeNode> nodes;
  final bool loading;
  final Object? error;
}

class KnowledgeListCubit extends Cubit<KnowledgeListState> {
  KnowledgeListCubit(this.store) : super(const KnowledgeListState());

  final KnowledgeStore store;
  late final StreamSubscription<void> _changesSubscription =
      store.changes.listen((_) => load());

  Future<void> load({String? query, String? tag}) async {
    emit(KnowledgeListState(nodes: state.nodes, loading: true));
    try {
      final nodes = await store.listNodes(query: query, tag: tag);
      emit(KnowledgeListState(nodes: nodes));
    } catch (error) {
      emit(KnowledgeListState(nodes: state.nodes, error: error));
    }
  }

  @override
  Future<void> close() async {
    await _changesSubscription.cancel();
    return super.close();
  }
}
