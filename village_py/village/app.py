import os
import time
from datetime import datetime
from functools import wraps

import requests
from bleach import clean
from bleach.sanitizer import ALLOWED_TAGS
from flask import (
    Flask,
    g,
    jsonify,
    redirect,
    render_template,
    request,
    send_from_directory,
    session,
    url_for,
)
from markdown import markdown
from PIL import Image

from village.images.thumbnails import make_and_save_thumbnail
from village.models.posts import (
    Message,
    PostID,
    ThreadScope,
    ThreadScopeOption,
    ThreadVisibility,
)
from village.models.users import Username
from village.post_graph import (
    calculate_final_messages,
    calculate_tail_context,
    calculate_thread_scope,
    calculate_thread_visible,
    extract_thread,
    only_root_posts,
)
from village.repository import Repository

OUR_ALLOWED_TAGS = frozenset(
    ALLOWED_TAGS | {"p", "em", "hr"} | {f"h{n}" for n in range(1, 6 + 1)}
)

app = Flask(__name__)
app.secret_key = os.environ["FLASK_SECRET_KEY"].encode("utf-8")
app.config["MAX_CONTENT_LENGTH"] = 16 * 1000 * 1000  # 16 MB


global_repository = Repository(os.path.expanduser("~/test-repository"))


def requires_logged_in_user(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        username = session.get("username", None)

        if not username:
            return redirect(url_for("index"))

        try:
            user = global_repository.users.load(username=username)
        except Exception as e:
            print(f"could not find user: {username}")
            return redirect(url_for("index"))

        g.user = user

        return f(*args, **kwargs)

    return wrapper


def maybe_logged_in_user(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        username = session.get("username", None)

        if username:
            try:
                user = global_repository.users.load(username=username)
            except Exception as e:
                print(f"could not find user: {username}")
                return redirect(url_for("index"))

        else:
            user = None

        g.user = user

        return f(*args, **kwargs)

    return wrapper


@app.route("/")
def index() -> str:
    return render_template("index.html")


@app.route("/uploads/<filename>")
def get_upload(filename: str):
    return send_from_directory(
        global_repository.uploads.path,
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

            auth = global_repository.auth.load(username=username)
            if not auth.check_password(password=password):
                raise Exception("password does not match")

            session["username"] = username

            if auth.new_password_required:
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

            auth = global_repository.auth.load(username=username)
            if not auth.check_password(password=current_password):
                raise Exception("current password does not match")

            auth.update_password(
                current_password=current_password, new_password=new_password
            )
            auth.new_password_required = False

            global_repository.auth.write(
                auth=auth,
                content="",
            )

            return redirect(url_for("logout"))

        except Exception as e:
            error = str(e)

    return render_template("update_password.html", username=username, error=error)


@app.route("/users")
@requires_logged_in_user
def list_users():
    users = global_repository.users.load_all()
    users.sort(key=lambda u: (u.display_name, u.username))

    return render_template("users.html", users=users)


@app.route("/users/<username>")
@requires_logged_in_user
def user_profile(username: Username):
    user = global_repository.users.load(username=username)
    content = clean(
        markdown(global_repository.users.load_content(username=username)),
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

                new_upload_filename = global_repository.uploads.new_filename(
                    suffix=extension
                )
                new_image_file.save(
                    global_repository.uploads.full_path_for(
                        filename=new_upload_filename
                    )
                )
                g.user.image_filename = new_upload_filename

                new_thumbnail_filename = global_repository.uploads.new_filename(
                    suffix=extension
                )
                make_and_save_thumbnail(
                    img,
                    global_repository.uploads.full_path_for(
                        filename=new_thumbnail_filename
                    ),
                )
                g.user.image_thumbnail = new_thumbnail_filename

            global_repository.users.write(user=g.user, content=new_content)

            return redirect(url_for("user_profile", username=username))

        except Exception as e:
            error = str(e)
            raise e

    content = clean(
        global_repository.users.load_content(username=g.user.username),
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


@app.route("/threads")
@maybe_logged_in_user
def list_threads():
    all_posts = global_repository.posts.all_posts()

    root_posts = only_root_posts(all_posts)
    root_posts.sort(key=lambda p: p.timestamp, reverse=True)
    # TODO: turn these root posts into some sort of structure that uses
    # calculate_thread_title and proably other useful methods to correctly
    # handle title changes and other fun features of message editing. Also we
    # should probably have other useful information about the thread, like time
    # of last message, or something. We'll be back here soon once we start
    # doing thread tags, too.

    if g.user is None:
        public_threads = [
            root_post
            for root_post in root_posts
            if calculate_thread_scope(
                extract_thread(all_posts=all_posts, root_post_id=root_post.id),
            )
            == ThreadScopeOption.PUBLIC
        ]

        return render_template(
            "threads.html", threads=public_threads, hidden_threads=[]
        )

    visible_threads = []
    hidden_threads = []
    for root_post in root_posts:
        if calculate_thread_visible(
            extract_thread(all_posts=all_posts, root_post_id=root_post.id),
        ):
            visible_threads.append(root_post)
        else:
            hidden_threads.append(root_post)

    return render_template(
        "threads.html",
        threads=visible_threads,
        hidden_threads=hidden_threads,
        user_can_post=g.user is not None,
    )


@app.route("/threads/<post_id>", methods=["GET", "POST"])
@maybe_logged_in_user
def show_thread(post_id: PostID):
    error = None

    all_posts = global_repository.posts.all_posts()
    if post_id not in all_posts or all_posts[post_id].context:
        return f"Root Post {post_id} not found", 400

    thread = extract_thread(
        all_posts=all_posts,  # type: ignore # but why??
        root_post_id=post_id,
    )

    if g.user is None:
        if not calculate_thread_scope(thread) == ThreadScopeOption.PUBLIC:
            return f"Root Post {post_id} not found", 400

    messages = calculate_final_messages(thread)

    new_title = f"re: {messages[0].title}"
    new_content = ""

    if g.user is not None and request.method == "POST":
        new_title = request.form["new_title"]
        new_content = request.form["new_content"]
        tail_context = request.form["tail_context"]

        try:
            if not new_title:
                raise Exception("a title is required")

            message = Message(
                id=global_repository.posts.new_post_id(),
                author=g.user.username,
                timestamp=datetime.utcnow(),
                title=new_title,
                context=[PostID(c) for c in tail_context.split(",")],
                upload_filename=None,
                replaces=None,
            )

            global_repository.posts.create(post=message, content=new_content)

            return redirect(url_for("show_thread", post_id=post_id))

        except Exception as e:
            error = str(e)

    message_contents = {
        message.id: clean(
            markdown(global_repository.posts.load_content(post_id=message.id)),
            tags=OUR_ALLOWED_TAGS,
        )
        for message in messages
    }

    users = {
        username: global_repository.users.load(username=username)
        for username in {message.author for message in messages}
    }

    return render_template(
        "thread.html",
        current_username=g.user.username if g.user is not None else None,
        user_can_administer=g.user is not None and thread[0].author == g.user.username,
        user_can_post=g.user is not None,
        logged_in_user=g.user is not None,
        thread_is_visible=calculate_thread_visible(thread),
        thread_scope=calculate_thread_scope(thread).value,
        messages=messages,
        message_contents=message_contents,
        tail_context=",".join(calculate_tail_context(thread)),
        new_title=new_title,
        new_content=new_content,
        users=users,
        error=error,
    )


@app.route("/threads/<root_post_id>/edit/<post_id_to_edit>", methods=["GET", "POST"])
@requires_logged_in_user
def edit_message(root_post_id: PostID, post_id_to_edit: PostID):
    error = None

    all_posts = global_repository.posts.all_posts()
    if root_post_id not in all_posts or all_posts[root_post_id].context:
        return f"Root Post {root_post_id} not found", 400

    thread = extract_thread(
        all_posts=all_posts,  # type: ignore # but why??
        root_post_id=root_post_id,
    )

    if post_id_to_edit not in {post.id for post in thread}:
        return f"Post {post_id_to_edit} not found in thread {root_post_id}", 400

    post_to_edit = all_posts[post_id_to_edit]
    assert isinstance(post_to_edit, Message)

    if post_to_edit.author != g.user.username:
        return redirect(url_for("show_thread", post_id=root_post_id))

    messages = calculate_final_messages(thread)

    updated_title = post_to_edit.title
    updated_content = global_repository.posts.load_content(post_id=post_id_to_edit)

    if request.method == "POST":
        updated_title = request.form["updated_title"]
        updated_content = request.form["updated_content"]
        tail_context = request.form["tail_context"]

        try:
            if not updated_title:
                raise Exception("a title is required")

            replacement_message = Message(
                id=global_repository.posts.new_post_id(),
                author=g.user.username,
                timestamp=datetime.utcnow(),
                title=updated_title,
                context=[PostID(c) for c in tail_context.split(",")],
                upload_filename=None,
                replaces=post_id_to_edit,
            )

            global_repository.posts.create(
                post=replacement_message, content=updated_content
            )

            return redirect(url_for("show_thread", post_id=root_post_id))

        except Exception as e:
            error = str(e)

    message_contents = {
        message.id: clean(
            markdown(global_repository.posts.load_content(post_id=message.id)),
            tags=OUR_ALLOWED_TAGS,
        )
        for message in messages
    }

    users = {
        username: global_repository.users.load(username=username)
        for username in {message.author for message in messages}
    }

    return render_template(
        "edit_message.html",
        post_id_to_edit=post_id_to_edit,
        messages=messages,
        message_contents=message_contents,
        updated_title=updated_title,
        updated_content=updated_content,
        tail_context=",".join(calculate_tail_context(thread)),
        users=users,
        error=error,
    )


def _add_thread_property(post_id: PostID, property_generator):
    all_posts = global_repository.posts.all_posts()
    if post_id not in all_posts:
        return f"Root Post {post_id} not found", 400

    if not all_posts[post_id].author == g.user.username:
        return redirect(url_for("show_thread", post_id=post_id))

    thread = extract_thread(
        all_posts=all_posts,  # type: ignore # but why??
        root_post_id=post_id,
    )
    thread_property = property_generator(thread)
    global_repository.posts.create(post=thread_property, content="")
    return redirect(url_for("show_thread", post_id=post_id))


@app.route("/threads/<post_id>/make_visible", methods=["GET"])
@requires_logged_in_user
def make_thread_visible(post_id: PostID):
    return _add_thread_property(
        post_id=post_id,
        property_generator=lambda thread: ThreadVisibility(
            id=global_repository.posts.new_post_id(),
            author=g.user.username,
            timestamp=datetime.utcnow(),
            context=calculate_tail_context(thread),
            visible=True,
        ),
    )


@app.route("/threads/<post_id>/make_hidden", methods=["GET"])
@requires_logged_in_user
def make_thread_hidden(post_id: PostID):
    return _add_thread_property(
        post_id=post_id,
        property_generator=lambda thread: ThreadVisibility(
            id=global_repository.posts.new_post_id(),
            author=g.user.username,
            timestamp=datetime.utcnow(),
            context=calculate_tail_context(thread),
            visible=False,
        ),
    )


@app.route("/threads/<post_id>/make_local", methods=["GET"])
@requires_logged_in_user
def make_thread_local(post_id: PostID):
    return _add_thread_property(
        post_id=post_id,
        property_generator=lambda thread: ThreadScope(
            id=global_repository.posts.new_post_id(),
            author=g.user.username,
            timestamp=datetime.utcnow(),
            context=calculate_tail_context(thread),
            scope=ThreadScopeOption.LOCAL,
        ),
    )


@app.route("/threads/<post_id>/make_public", methods=["GET", "POST"])
@requires_logged_in_user
def make_thread_public(post_id: PostID):
    all_posts = global_repository.posts.all_posts()
    if post_id not in all_posts:
        return f"Root Post {post_id} not found", 400

    if not all_posts[post_id].author == g.user.username:
        return redirect(url_for("show_thread", post_id=post_id))

    thread = extract_thread(
        all_posts=all_posts,  # type: ignore # but why??
        root_post_id=post_id,
    )

    if request.method == "POST":
        confirmed = request.form.get("confirmed") == "confirmed"

        if not confirmed:
            return redirect(url_for("show_thread", post_id=post_id))

        thread_scope = ThreadScope(
            id=global_repository.posts.new_post_id(),
            author=g.user.username,
            timestamp=datetime.utcnow(),
            context=calculate_tail_context(thread),
            scope=ThreadScopeOption.PUBLIC,
        )
        global_repository.posts.create(post=thread_scope, content="")

        return redirect(url_for("show_thread", post_id=post_id))

    return render_template(
        "make_thread_public.html",
        post_id=post_id,
    )


@app.route("/threads/<post_id>/delete", methods=["GET", "POST"])
@requires_logged_in_user
def delete_thread(post_id: PostID):
    all_posts = global_repository.posts.all_posts()
    if post_id not in all_posts:
        return f"Root Post {post_id} not found", 400

    if not all_posts[post_id].author == g.user.username:
        return redirect(url_for("show_thread", post_id=post_id))

    thread = extract_thread(
        all_posts=all_posts,  # type: ignore # but why??
        root_post_id=post_id,
    )

    if request.method == "POST":
        confirmed = request.form.get("confirmed") == "confirmed"

        if not confirmed:
            return redirect(url_for("show_thread", post_id=post_id))

        for post in thread:
            global_repository.posts.delete(post_id=post.id)

        return redirect(url_for("list_threads"))

    return render_template(
        "delete_thread.html",
        post_id=post_id,
    )


@app.route("/threads/new", methods=["GET", "POST"])
@requires_logged_in_user
def new_post():
    error = None

    title = ""
    content = ""

    if request.method == "POST":
        title = request.form["title"]
        content = request.form["content"]
        visible = request.form.get("visible") is not None

        try:
            if not title:
                raise Exception("a title is required")

            message = Message(
                id=global_repository.posts.new_post_id(),
                author=g.user.username,
                timestamp=datetime.utcnow(),
                title=title,
                context=[],
                upload_filename=None,
                replaces=None,
            )
            global_repository.posts.create(post=message, content=content)

            if not visible:
                thread_visibility = ThreadVisibility(
                    id=global_repository.posts.new_post_id(),
                    author=g.user.username,
                    timestamp=datetime.utcnow(),
                    context=[message.id],
                    visible=False,
                )
                global_repository.posts.create(post=thread_visibility, content="")

            return redirect(url_for("show_thread", post_id=message.id))

        except Exception as e:
            error = str(e)

    return render_template(
        "new_thread.html",
        title=title,
        content=content,
        error=error,
    )


@app.route("/chat", methods=["GET"])
@requires_logged_in_user
def chat_view():
    return render_template(
        "chat.html",
    )


@app.route("/chat/poll", methods=["POST"])
@requires_logged_in_user
def chat_poll():
    timeout = time.time() + 5

    data = request.get_json()

    command = data.get("command", "UNKNOWN")
    try:
        since = int(data.get("since_microseconds", "0"))
    except:
        since = 0

    if command == "list":
        while time.time() < timeout:
            result = requests.get(
                f"http://localhost:54321/messages?since_microseconds={since}"
            )
            result.raise_for_status()
            messages = result.json()
            if messages:
                return jsonify(
                    {
                        "messages": messages,
                    },
                )
            time.sleep(0.1)

        return jsonify({})

    if command == "add":
        result = requests.post(
            f"http://localhost:54321/add_message?since_microseconds={since}",
            json={
                "author": g.user.username,
                "message": data["message"],
            },
        )
        result.raise_for_status()
        messages = result.json()

        return jsonify(
            {
                "messages": messages,
            },
        )

    raise Exception(f"unknown command: {command}")
