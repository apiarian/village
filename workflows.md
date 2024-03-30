# Workflows

Describes the various workflows that the system supports.

## User Creation
The administrator creates a entry in the users database [database.md](Database-Users) with a temporary password, setting the `new_password_required` field to true.

## User Login
The user hits the `/login` endpoint with their username and password. The password is salted and checked on the backend against the data in their file. If the user is marked as `new_password_required`, they are redirected to the `/update_password` page, which will take their current password and a new one, and update their information, clearing the `new_password_required` setting. In the end, the user is redirected to the home page with a session cookie.