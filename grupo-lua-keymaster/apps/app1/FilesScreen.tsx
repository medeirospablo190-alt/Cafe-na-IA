import { useState } from "react";
import { FilesScreen as FilesScreenV3 } from "./FilesScreenV3";
import { TextFileImporter } from "./TextFileImporter";

export function FilesScreen({
  sessionToken,
  deviceToken,
  profileId
}: {
  sessionToken: string;
  deviceToken: string;
  profileId: string | null;
}) {
  const [revision, setRevision] = useState(0);

  return (
    <>
      <TextFileImporter
        sessionToken={sessionToken}
        deviceToken={deviceToken}
        onSaved={() => setRevision((value) => value + 1)}
      />
      <FilesScreenV3
        key={revision}
        sessionToken={sessionToken}
        deviceToken={deviceToken}
        profileId={profileId}
      />
    </>
  );
}
