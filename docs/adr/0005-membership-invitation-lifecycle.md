# Represent invitations as pending memberships

The task-manager domain uses one Membership lifecycle record: Invited grants no access, acceptance makes it Active, and decline, expiry, or revocation is terminal. This keeps invitation execution and membership activation on one durable FSM record while preserving terminal history; reinviting after a terminal result creates a new record.
