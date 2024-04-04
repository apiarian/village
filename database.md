# Database

The Village uses a plain filesystem with text files as the database. This is quite sufficient for the number of users we intend to support on a single server. Some in-memory caching is likely required for indexing.

The database is stored within the files and subdirectories of a root: `*DATABASE*`. This should be a directory that the server has read and write access to. Other tools may be allowed to read or write the directory as well, though concurrent writes to the same files should be avoided if possible. The main server process needs to be able to detect updates to the database by other programs.

In general, files should be encoded with UTF-8. Structured data is stored in yaml format. When yaml and text data are combined, we use a `------` (six dashes) as the delimiter between them.

## Users

Stored in the `*DATABASE*/users/` directory. Formatted as `[username].yaml`.

- `username` (string) - Can only have ASCII letters, numbers, and the underscore. Must be at least one character long.
- `display_name` (string) - The way the user's name is actually displayed in long-form
- `password_salt` (binary, hex-encoded string) - The salt used to encrypt the user's password.
- `encrypted_password` (binary, hex-encoded string) - The user's password, salted (with `password_salt`) and encrypted using `scrypt`.
- `new_password_required` (boolean) - Indicates if the password needs to be updated next time the user logs in. 

The body of the file is a markdown document which is used for the user's profile page.  
