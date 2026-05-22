import 'package:flutter/material.dart';
import '../../data/models/department_node.dart';
import '../../data/department_filter_service.dart';

/// Widget to display user departments in Home Screen
class UserDepartmentsWidget extends StatefulWidget {
  final Map<String, dynamic> meResponse;
  final List<dynamic> centers;
  final List<dynamic> faculties;
  final List<dynamic> departments;
  final Function(DepartmentNode)? onDepartmentTap;

  const UserDepartmentsWidget({
    super.key,
    required this.meResponse,
    required this.centers,
    required this.faculties,
    required this.departments,
    this.onDepartmentTap,
  });

  @override
  State<UserDepartmentsWidget> createState() => _UserDepartmentsWidgetState();
}

class _UserDepartmentsWidgetState extends State<UserDepartmentsWidget> {
  late final List<DepartmentNode> _userDepartments;

  @override
  void initState() {
    super.initState();
    _userDepartments = DepartmentFilterService.getUserDepartments(
      meResponse: widget.meResponse,
      centers: widget.centers,
      faculties: widget.faculties,
      departments: widget.departments,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userDepartments.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _userDepartments.length,
      itemBuilder: (context, index) {
        return _DepartmentTreeItem(
          node: _userDepartments[index],
          level: 0,
          onTap: widget.onDepartmentTap,
        );
      },
    );
  }
}

class _DepartmentTreeItem extends StatelessWidget {
  final DepartmentNode node;
  final int level;
  final Function(DepartmentNode)? onTap;

  const _DepartmentTreeItem({
    required this.node,
    required this.level,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onTap?.call(node),
          child: Container(
            margin: EdgeInsets.only(
              left: level * 16.0,
              top: 4,
              bottom: 4,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                if (node.image != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      node.image!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    ),
                  )
                else
                  _buildPlaceholder(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (node.stats.isNotEmpty)
                        Text(
                          '${node.stats['courses'] ?? 0} courses',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasChildren)
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
              ],
            ),
          ),
        ),
        // Recursive children
        if (hasChildren)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: node.children.map((child) {
                return _DepartmentTreeItem(
                  node: child,
                  level: level + 1,
                  onTap: onTap,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.folder_outlined,
        color: Colors.grey.shade400,
      ),
    );
  }
}

/// Simplified horizontal scroll version for Home Screen
class UserSubjectsHorizontal extends StatelessWidget {
  final Map<String, dynamic> meResponse;
  final List<dynamic> centers;
  final List<dynamic> faculties;
  final List<dynamic> departments;
  final Function(DepartmentNode)? onSubjectTap;

  const UserSubjectsHorizontal({
    super.key,
    required this.meResponse,
    required this.centers,
    required this.faculties,
    required this.departments,
    this.onSubjectTap,
  });

  @override
  Widget build(BuildContext context) {
    final userDepartments = DepartmentFilterService.getUserDepartments(
      meResponse: meResponse,
      centers: centers,
      faculties: faculties,
      departments: departments,
    );

    if (userDepartments.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: userDepartments.length,
        itemBuilder: (context, index) {
          final dept = userDepartments[index];
          return _SubjectCard(
            department: dept,
            onTap: () => onSubjectTap?.call(dept),
          );
        },
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final DepartmentNode department;
  final VoidCallback? onTap;

  const _SubjectCard({
    required this.department,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: department.image != null
                  ? Image.network(
                      department.image!,
                      height: 120,
                      width: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
            ),
            const SizedBox(height: 8),
            // Name
            Text(
              department.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // Stats
            if (department.stats.isNotEmpty)
              Text(
                '${department.stats['courses'] ?? 0} courses',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      height: 120,
      width: 160,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.folder_outlined,
        size: 40,
        color: Colors.grey.shade400,
      ),
    );
  }
}
