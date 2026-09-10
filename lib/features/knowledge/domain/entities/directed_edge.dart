class DirectedEdge {
  const DirectedEdge({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.relation,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String fromId;
  final String toId;
  final String relation;
  final DateTime createdAt;
  final DateTime updatedAt;
}
