from datetime import datetime
from typing import NamedTuple, Optional

from dateutil.parser import parse
from icalendar import Calendar
from icalendar import Event as iCalEvent
from icalendar import vDatetime

from village.models.posts import Message, PostID
from village.models.threads import Thread
from village.models.users import Username
from village.repositories.posts import PostsRepository
from village.repositories.uploads import UploadsRepository
from village.repositories.users import UsersRepository

CALENDAR_USERNAME = Username("calendar")


class Event(NamedTuple):
    title: str
    start: datetime
    end: datetime
    location: str
    description: str
    reactions: str | None

    def to_ical_event(self, base_post_id: PostID) -> iCalEvent:
        event = iCalEvent()
        event.add("uid", base_post_id)
        event.add("summary", self.title)
        event.add("dtstart", vDatetime(self.start))
        event.add("dtend", vDatetime(self.end))
        event.add("location", self.location)

        description = self.description
        if self.reactions:
            description = description + "\n\n" + self.reactions
        event.add("description", description)

        event.add("dtstamp", vDatetime(datetime.utcnow()))

        return event


def _base_calendar() -> Calendar:
    cal = Calendar()
    cal.add("prodid", "village.megamicron.net/calendar")
    cal.add("version", "2.0")
    cal.add("calscale", "GREGORIAN")
    cal.add("method", "PUBLISH")
    cal.add("X-PUBLISHED-TTL", "PT1H")

    return cal


def generate_full_calendar(
    posts: PostsRepository, uploads: UploadsRepository
) -> Calendar:
    all_posts = posts.all_posts()

    cal = _base_calendar()

    for post in all_posts.values():
        if not isinstance(post, Message):
            continue

        if post.author != CALENDAR_USERNAME:
            continue

        if post.is_tombstone:
            continue

        if any(
            isinstance(p, Message) and p.replaces == post.id for p in all_posts.values()
        ):
            continue

        if (not post.upload_filename) or (not post.upload_filename.endswith(".ics")):
            continue

        with open(uploads.full_path_for(filename=post.upload_filename), "rb") as f:
            post_calendar = Calendar.from_ical(f.read(), multiple=False)  # type: ignore # definitely works
            for event in post_calendar.events:
                cal.add_component(event)

    return cal


def handle_new_message(
    posts: PostsRepository, uploads: UploadsRepository, message: Message, content: str
) -> None:
    event = _parse_content(message.title, content, None)
    if event is None:
        return

    cal = _base_calendar()
    cal.add_component(event.to_ical_event(message.id))

    ics_filename = uploads.new_filename(suffix=".ics")
    with open(uploads.full_path_for(filename=ics_filename), "wb") as f:
        f.write(cal.to_ical())

    event_message = Message(
        id=posts.new_post_id(),
        author=CALENDAR_USERNAME,
        timestamp=datetime.utcnow(),
        title=f"cal: {message.title}",
        context=[message.id],
        upload_filename=ics_filename,
        preview_filename=None,
        replaces=None,
        is_tombstone=False,
    )
    posts.create(post=event_message, content="Parsed Event")


def handle_replacement_message(
    posts: PostsRepository, uploads: UploadsRepository, message: Message, content: str
) -> None:
    all_posts = posts.all_posts()

    related_event_messages: list[Message] = []
    if message.replaces:
        for _, post in all_posts.items():
            if (
                (message.replaces in post.context)
                and isinstance(post, Message)
                and post.author == CALENDAR_USERNAME
            ):
                assert isinstance(post, Message)
                related_event_messages.append(post)

    previous_event_message: Optional[Message] = None

    if related_event_messages:
        previous_event_message = sorted(
            related_event_messages, key=lambda message: message.timestamp
        )[-1]

    event = _parse_content(message.title, content, None)
    if event is None:
        if previous_event_message is None:
            return

        tombstone = Message(
            id=posts.new_post_id(),
            author=CALENDAR_USERNAME,
            timestamp=datetime.utcnow(),
            title=f"TOMBSTONE: {previous_event_message.title}",
            context=previous_event_message.context + [previous_event_message.id],
            upload_filename=None,
            preview_filename=None,
            replaces=previous_event_message.id,
            is_tombstone=True,
        )
        posts.create(
            post=tombstone,
            content="a calendar event was deleted here",
        )

        return

    root_message = message
    while root_message.replaces:
        previous_post = all_posts[root_message.replaces]
        assert isinstance(previous_post, Message)
        root_message = previous_post

    cal = _base_calendar()
    cal.add_component(event.to_ical_event(root_message.id))

    ics_filename = uploads.new_filename(suffix=".ics")
    with open(uploads.full_path_for(filename=ics_filename), "wb") as f:
        f.write(cal.to_ical())

    event_message = Message(
        id=posts.new_post_id(),
        author=CALENDAR_USERNAME,
        timestamp=datetime.utcnow(),
        title=f"cal: {message.title}",
        context=[message.id],
        upload_filename=ics_filename,
        preview_filename=None,
        replaces=previous_event_message.id if previous_event_message else None,
        is_tombstone=False,
    )
    posts.create(post=event_message, content=f"Parsed Event (updated)")


def handle_message_reaction(
    *,
    posts: PostsRepository,
    users: UsersRepository,
    uploads: UploadsRepository,
    root_post_id: PostID,
    post_id_to_react: PostID,
    reaction_id: PostID,
) -> None:
    all_posts = posts.all_posts()

    original_post = all_posts[post_id_to_react]

    if not isinstance(original_post, Message):
        return

    event_messages: list[Message] = []
    for _, post in all_posts.items():
        if (
            isinstance(post, Message)
            and post.author == CALENDAR_USERNAME
            and post_id_to_react in post.context
        ):
            event_messages.append(post)

    if not event_messages:
        return

    latest_event_message = sorted(
        event_messages, key=lambda message: message.timestamp
    )[-1]

    thread = Thread.extract_thread(all_posts=all_posts, root_post_id=root_post_id)

    if post_id_to_react not in {post.id for post in thread.posts}:
        return

    reactions = thread.reactions().get(post_id_to_react, {})

    inverted_reactions: dict[str, set[Username]] = {}
    for username, reaction_strings in reactions.items():
        for reaction_string in reaction_strings:
            if reaction_string not in inverted_reactions:
                inverted_reactions[reaction_string] = set()
            inverted_reactions[reaction_string].add(username)

    reaction_block = "\n".join(
        f"{reaction_string}: {', '.join(sorted(users.load(username=username).display_name for username in usernames))}"
        for reaction_string, usernames in inverted_reactions.items()
    )

    event = _parse_content(
        original_post.title,
        posts.load_content(post_id=original_post.id),
        reaction_block,
    )

    if event is None:
        return

    cal = _base_calendar()
    cal.add_component(event.to_ical_event(original_post.id))

    ics_filename = uploads.new_filename(suffix=".ics")
    with open(uploads.full_path_for(filename=ics_filename), "wb") as f:
        f.write(cal.to_ical())

    event_message = Message(
        id=posts.new_post_id(),
        author=CALENDAR_USERNAME,
        timestamp=datetime.utcnow(),
        title=f"cal: {original_post.title}",
        context=[original_post.id, latest_event_message.id, reaction_id],
        upload_filename=ics_filename,
        preview_filename=None,
        replaces=latest_event_message.id,
        is_tombstone=False,
    )
    posts.create(post=event_message, content="Parsed Event (updated)")


CALENDAR_EVENT_TEMPLATE = """\
- Start: 2026-01-01 17:00
- End: 2026-01-01 18:00
- Location: optional, but maybe helpful

A description goes here, after a blank line.
"""


def _parse_content(title: str, content: str, reactions: str | None) -> Optional[Event]:
    lines = content.splitlines()

    start: Optional[datetime] = None
    end: Optional[datetime] = None
    location: Optional[str] = None
    description_lines: list[str] = []
    seen_empty_line = False
    for line in lines:
        start_prefix = "- Start: "
        if line.startswith(start_prefix):
            try:
                start_value = line[len(start_prefix) :]
                start = parse(start_value)
            except Exception as e:
                print(f"could not parse start value {start_value}: {e}")
            continue

        end_prefix = "- End: "
        if line.startswith(end_prefix):
            try:
                end_value = line[len(end_prefix) :]
                end = parse(end_value)
            except Exception as e:
                print(f"could not parse end value {end_value}: {e}")
            continue

        location_prefix = "- Location: "
        if line.startswith(location_prefix):
            location = line[len(location_prefix) :]
            continue

        if line == "":
            seen_empty_line = True
            continue

        if seen_empty_line:
            description_lines.append(line)

    if start and end and location:
        return Event(
            title=title,
            start=start,
            end=end,
            location=location,
            description="\n".join(description_lines),
            reactions=reactions,
        )

    return None
