/// Only an explicit current IM member role proves group membership.
/// A profile shell can carry a user ID with an undefined (0/null) role.
bool isConfirmedGroupMemberRole(int? role) =>
    role == 200 || role == 300 || role == 400;
