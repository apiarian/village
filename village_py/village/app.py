import os
from functools import wraps

from bleach import clean
from bleach.sanitizer import ALLOWED_TAGS
from flask import (
    Flask,
    g,
    redirect,
    render_template,
    request,
    send_from_directory,
    session,
    url_for,
)
from markdown import markdown
from PIL import Image

from village.models.users import Username
from village.repository import Repository

OUR_ALLOWED_TAGS = frozenset(
    ALLOWED_TAGS | {"p", "em", "hr"} | {f"h{n}" for n in range(1, 6 + 1)}
)

app = Flask(__name__)
app.secret_key = os.environ["FLASK_SECRET_KEY"].encode("utf-8")
app.config["MAX_CONTENT_LENGTH"] = 16 * 1000 * 1000  # 16 MB


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


@app.route("/uploads/<filename>")
def get_upload(filename: str):
    return send_from_directory(
        global_repository.uploads_path,
        filename,
    )


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
    users.sort(key=lambda u: (u.display_name, u.username))

    return render_template("users.html", users=users)


@app.route("/users/<username>")
@requires_logged_in_user
def user_profile(username: Username):
    user = global_repository.load_user(username=username)
    content = clean(
        markdown(global_repository.load_user_content(username=username)),
        tags=OUR_ALLOWED_TAGS,
    )

    return render_template("user_profile.html", user=user, content=content)


@app.route("/users/<username>/edit", methods=["GET", "POST"])
@requires_logged_in_user
def edit_user_profile(username: Username):
    if username != g.user.username:
        return redirect(url_for("list_users"))

    error = None

    if request.method == "POST":
        form_username = request.form["username"]
        new_display_name = request.form["display_name"]
        new_content = request.form["content"]

        raw_image = request.files["image"]
        new_image = raw_image if raw_image.filename != "" else None

        try:
            if form_username != g.user.username:
                raise Exception("cannot change the username")

            if not new_display_name:
                raise Exception("display name must not be empty")

            g.user.display_name = new_display_name

            if new_image:
                if not new_image.filename:
                    raise Exception("somehow missing an image filename")

                _, extension = os.path.splitext(new_image.filename)

                img = Image.open(
                    new_image,
                    formats=(
                        "GIF",
                        "JPEG",
                        "PNG",
                    ),
                )
                img.load()
                new_image.seek(0)

                new_upload_filename = global_repository.new_upload_filename(
                    suffix=extension
                )

                new_image.save(
                    global_repository.upload_path_for(filename=new_upload_filename)
                )

                g.user.image_filename = new_upload_filename

                extra_frames = []
                if not hasattr(img, "n_frames"):
                    thumbnail = img.copy()
                    thumbnail.thumbnail((50, 50), resample=Image.Resampling.LANCZOS)

                    new_thumbnail_filename = global_repository.new_upload_filename(
                        suffix=extension
                    )
                    with open(
                        global_repository.upload_path_for(
                            filename=new_thumbnail_filename
                        ),
                        "wb",
                    ) as f:
                        thumbnail.save(f, format=img.format)

                else:
                    thumbnail = img.copy()
                    thumbnail.thumbnail((50, 50), resample=Image.Resampling.LANCZOS)

                    for frame in range(1, img.n_frames):
                        img.seek(frame)
                        extra_frame = img.copy()
                        extra_frame.thumbnail(
                            (50, 50), resample=Image.Resampling.LANCZOS
                        )
                        extra_frames.append(extra_frame)

                    new_thumbnail_filename = global_repository.new_upload_filename(
                        suffix=extension
                    )
                    with open(
                        global_repository.upload_path_for(
                            filename=new_thumbnail_filename
                        ),
                        "wb",
                    ) as f:
                        thumbnail.save(
                            f,
                            format=img.format,
                            save_all=True,
                            append_images=extra_frames,
                        )

                g.user.image_thumbnail = new_thumbnail_filename

            global_repository.update_user(user=g.user)
            global_repository.update_user_content(
                username=g.user.username, content=new_content
            )

            return redirect(url_for("user_profile", username=username))

        except Exception as e:
            error = str(e)

    content = clean(
        global_repository.load_user_content(username=g.user.username),
        tags=OUR_ALLOWED_TAGS,
    )

    return render_template(
        "user_profile_editable.html", error=error, user=g.user, content=content
    )


@app.route("/logout")
@requires_logged_in_user
def logout():
    session.pop("username", None)
    return redirect(url_for("index"))
