import os
from flask import Flask, render_template, request, session, redirect, url_for
from .repository import Repository
from .models.users import Username

app = Flask(__name__)
app.secret_key = os.environ["FLASK_SECRET_KEY"].encode("utf-8")


global_repository = Repository(os.path.expanduser("~/test-repository"))


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


@app.route("/logout")
def logout():
    session.pop("username", None)
    return redirect(url_for("index"))
