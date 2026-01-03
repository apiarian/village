import yaml

from village.repositories.base import FilesRepository


class YAMLandText(FilesRepository):
    YAML_SUFFIX = ".yaml"
    CONTENT_SEPARATOR = "------\n"

    def _write_data_and_content(
        self, *, full_path: str, data: dict, content: str
    ) -> None:
        with open(full_path, "wt") as f:
            yaml.dump(data, f)

            f.write(self.CONTENT_SEPARATOR)

            f.write(content)

    def _load_raw_data(self, *, full_path: str) -> dict:
        with open(full_path, "rt") as f:
            yaml_lines: list[str] = []
            for line in f:
                if line == self.CONTENT_SEPARATOR:
                    return yaml.safe_load("".join(yaml_lines))

                yaml_lines.append(line)

        raise Exception(f"no {self.CONTENT_SEPARATOR} in {full_path}")

    def _load_raw_content(self, *, full_path: str) -> str:
        with open(full_path, "rt") as f:
            for line in f:
                if line == self.CONTENT_SEPARATOR:
                    break

            return "".join(f)
