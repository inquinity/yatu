# Unreleased

The build number shown in About and in the settings footer now means something.

`CFBundleVersion` was reset to 1 on every version change, so 1.0.0, 1.0.1 and
1.0.2 all shipped as **build 1** — the field carried no information, nothing
could order two copies of Yatu by it, and a local build was indistinguishable
from the release it was built on. It is now a single monotonic integer that only
ever goes up, which is what the field is for.
