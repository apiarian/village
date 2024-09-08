import os
from functools import wraps
from datetime import datetime

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
from village.models.posts import PostID, Post
from village.repository import Repository
from village.images.thumbnails import make_and_save_thumbnail
from village.post_graph import calculate_tail_context

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
        new_image_file = raw_image if raw_image.filename != "" else None

        try:
            if form_username != g.user.username:
                raise Exception("cannot change the username")

            if not new_display_name:
                raise Exception("display name must not be empty")

            g.user.display_name = new_display_name

            if new_image_file:
                if not new_image_file.filename:
                    raise Exception("somehow missing an image filename")

                _, extension = os.path.splitext(new_image_file.filename)

                img = Image.open(
                    new_image_file,
                    formats=(
                        "GIF",
                        "JPEG",
                        "PNG",
                    ),
                )
                img.load()
                new_image_file.seek(0)

                new_upload_filename = global_repository.new_upload_filename(
                    suffix=extension
                )
                new_image_file.save(
                    global_repository.upload_path_for(filename=new_upload_filename)
                )
                g.user.image_filename = new_upload_filename

                new_thumbnail_filename = global_repository.new_upload_filename(
                    suffix=extension
                )
                make_and_save_thumbnail(
                    img,
                    global_repository.upload_path_for(filename=new_thumbnail_filename),
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


@app.route("/posts")
@requires_logged_in_user
def list_posts():
    posts = global_repository.load_all_top_level_posts()
    posts.sort(key=lambda p: p.timestamp)

    return render_template("posts.html", posts=posts)


@app.route("/posts/<post_id>", methods=["GET", "POST"])
@requires_logged_in_user
def post_list(post_id: PostID):
    error = None

    posts = global_repository.load_posts(top_post_id=post_id)

    post_contents = {
        post.id: clean(
            markdown(global_repository.load_post_content(post_id=post.id)),
            tags=OUR_ALLOWED_TAGS,
        )
        for post in posts
    }

    new_title = f"re: {posts[0].title}"
    new_content = ""

    if request.method == "POST":
        new_title = request.form["new_title"]
        new_content = request.form["new_content"]
        tail_context = request.form["tail_context"]

        try:
            if not new_title:
                raise Exception("a title is required")

            new_post = Post(
                id=global_repository.new_post_id(),
                author=g.user.username,
                timestamp=datetime.utcnow(),
                title=new_title,
                context=[PostID(c) for c in tail_context.split(",")],
                upload_filename=None,
            )

            global_repository.create_post(post=new_post, content=new_content)

            return redirect(url_for("post_list", post_id=post_id))

        except Exception as e:
            error = str(e)

    return render_template(
        "post.html",
        posts=posts,
        post_contents=post_contents,
        tail_context=",".join(calculate_tail_context(posts)),
        new_title=new_title,
        new_content=new_content,
        error=error,
    )


@app.route("/posts/new", methods=["GET", "POST"])
@requires_logged_in_user
def new_post():
    error = None

    title = ""
    content = ""

    if request.method == "POST":
        title = request.form["title"]
        content = request.form["content"]

        try:
            if not title:
                raise Exception("a title is required")

            post = Post(
                id=global_repository.new_post_id(),
                author=g.user.username,
                timestamp=datetime.utcnow(),
                title=title,
                context=[],
                upload_filename=None,
            )

            global_repository.create_post(post=post, content=content)

            return redirect(url_for("post_list", post_id=post.id))

        except Exception as e:
            error = str(e)

    return render_template(
        "new_post.html",
        title=title,
        content=content,
        error=error,
    )
