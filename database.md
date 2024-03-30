# Database

The Village uses a plain filesystem with text files as the database. This is quite sufficient for the number of users we intend to support on a single server. Some in-memory caching is likely required for indexing.

The database is stored within the files and subdirectories of a root: `*DATABASE*`. This should be a directory that the server has read and write access to. Other tools may be allowed to read or write the directory as well, though concurrent writes to the same files should be avoided if possible. The main server process needs to be able to detect updates to the database by other programs.

## Users

... and other stuff.