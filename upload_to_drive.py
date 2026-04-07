from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# Path to your service account JSON
SERVICE_ACCOUNT_FILE = 'sa.json'  # In GitHub Actions, you can write it to this path first
FOLDER_ID = '1EVIHk24_3C7DsCLcYoQOdrM_T11UrkWH'  # Your Drive folder ID
FILE_PATH = 'spotify.png'  # File to upload
FILE_NAME = 'spotify.png'  # Name on Drive

# Authenticate with the service account
credentials = service_account.Credentials.from_service_account_file(
    SERVICE_ACCOUNT_FILE,
    scopes=['https://www.googleapis.com/auth/drive']
)

# Build the Drive API client
service = build('drive', 'v3', credentials=credentials)

# Create file metadata
file_metadata = {
    'name': FILE_NAME,
    'parents': [FOLDER_ID]  # Specify folder
}

# Upload the file
media = MediaFileUpload(FILE_PATH, resumable=True)
file = service.files().create(body=file_metadata, media_body=media, fields='id').execute()

print(f"Uploaded file with ID: {file.get('id')}")
