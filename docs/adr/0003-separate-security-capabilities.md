# Separate security capabilities

Model Cryptography, Key Management, Authentication, and Authorization as distinct capabilities under Security; authentication may depend on crypto and key-management ports but is not itself a cryptographic primitive. Applications own end-user accounts and domain authorization, while the framework keeps workload identity separate.
