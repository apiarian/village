import os
from flask import Flask, render_template, request, session, redirect, url_for, g
from village.repository import Repository
from village.models.users import Username
from functools import wraps

app = Flask(__name__)
app.secret_key = os.environ["FLASK_SECRET_KEY"].encode("utf-8")


global_repository = Repository(os.path.expanduser("~/test-repository"))
global_repository.load_all_users()


def requires_logged_in_user(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        username = session.get("username", None)

        if not username:
            return redirect(url_for("index"))

        try:
            user = global_repository.load_user(username=username)
        except Exception as e:
            print(f"could not find user: {username}")
            return redirect(url_for("index"))

        g.user = user

        return f(*args, **kwargs)

    return wrapper


@app.route("/")
def index() -> str:
    return render_template("index.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    username = None

    if request.method == "POST":
        try:
            username = Username(request.form["username"])
            password = request.form["password"]

            user = global_repository.load_user(username=username)
            if not user.check_password(password=password):
                raise Exception("password does not match")

            session["username"] = username

            if user.new_password_required:
                return redirect(url_for("update_password"))

            return redirect(url_for("index"))

        except Exception as e:
            error = str(e)

    return render_template("login.html", username=username, error=error)


@app.route("/update_password", methods=["GET", "POST"])
@requires_logged_in_user
def update_password():
    error = None

    username = session.get("username", None)
    if not username:
        return redirect(url_for("index"))

    username = Username(username)

    if request.method == "POST":
        try:
            current_password = request.form["current_password"]
            new_password = request.form["new_password"]
            new_password_again = request.form["new_password_again"]

            if new_password != new_password_again:
                raise Exception("new passwords do not match")

            user = global_repository.load_user(username=username)
            if not user.check_password(password=current_password):
                raise Exception("current password does not match")

            user.update_password(
                current_password=current_password, new_password=new_password
            )
            user.new_password_required = False

            global_repository.update_user(user=user)

            return redirect(url_for("logout"))

        except Exception as e:
            error = str(e)

    return render_template("update_password.html", username=username, error=error)


@app.route("/users")
@requires_logged_in_user
def list_users():
    users = global_repository.load_all_users()
    users.sort(key=lambda u: u.username)

    return render_template("users.html", users=users)


@app.route("/users/<username>", methods=["GET", "POST"])
@requires_logged_in_user
def user_profile(username: Username):
    if username == g.user.username:
        return handle_editable_user_profile()

    user = global_repository.load_user(username=username)

    return render_template("user_profile.html", user=user)


def handle_editable_user_profile():
    error = None

    if request.method == "POST":
        username = request.form["username"]
        new_display_name = request.form["display_name"]

        try:
            if username != g.user.username:
                raise Exception("cannot edit other people's profiles")

            if not new_display_name:
                raise Exception("display name must not be empty")

            g.user.display_name = new_display_name

            global_repository.update_user(user=g.user)

        except Exception as e:
            error = str(e)

    return render_template("user_profile_editable.html", error=error, user=g.user)


@app.route("/logout")
@requires_logged_in_user
def logout():
    session.pop("username", None)
    return redirect(url_for("index"))
