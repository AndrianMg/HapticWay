import os
import sys
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError

# If modifying these scopes, delete the token file.
# 'https://www.googleapis.com/auth/drive.file' allows creation and editing of files created by the app.
SCOPES = ['https://www.googleapis.com/auth/drive.file']

# Token lives in the user's home directory, NOT the repo, so it can never be committed.
TOKEN_PATH = os.path.join(os.path.expanduser('~'), '.hapticway_drive_token.json')

def get_credentials():
    """Gets valid user credentials from storage or runs OAuth flow."""
    creds = None
    # The token file stores the user's access and refresh tokens, and is
    # created automatically when the authorization flow completes for the first time.
    if os.path.exists(TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
    
    # If there are no (valid) credentials available, let the user log in.
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists('credentials.json'):
                print("Error: 'credentials.json' not found in the current directory.")
                print("Please download your OAuth 2.0 client credentials from the Google Cloud Console")
                print("and place them in this directory as 'credentials.json'.")
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file('credentials.json', SCOPES)
            creds = flow.run_local_server(port=0)
        # Save the credentials for the next run
        with open(TOKEN_PATH, 'w') as token:
            token.write(creds.to_json())
            
    return creds

def upload_file(local_path, drive_filename=None, folder_id=None, mimetype=None):
    """
    Uploads a file to Google Drive.
    
    Parameters:
        local_path (str): Path to the local file to upload.
        drive_filename (str): Name to give the file in Google Drive. Defaults to the local filename.
        folder_id (str): Optional Google Drive folder ID to upload the file into.
        mimetype (str): Optional MIME type of the file. If None, it will be guessed by the API.
    """
    if not os.path.exists(local_path):
        print(f"Error: Local file '{local_path}' does not exist.")
        return None

    # Default drive filename to local filename if not specified
    if not drive_filename:
        drive_filename = os.path.basename(local_path)

    creds = get_credentials()

    try:
        # Build the Drive API service
        service = build('drive', 'v3', credentials=creds)

        # Configure file metadata
        file_metadata = {'name': drive_filename}
        if folder_id:
            file_metadata['parents'] = [folder_id]

        # Prepare the media file upload
        media = MediaFileUpload(local_path, mimetype=mimetype, resumable=True)

        print(f"Uploading '{local_path}' to Google Drive as '{drive_filename}'...")
        
        # Execute the upload request
        file = service.files().create(
            body=file_metadata,
            media_body=media,
            fields='id, webViewLink'
        ).execute()

        print("Upload successful!")
        print(f"File ID: {file.get('id')}")
        print(f"Web View Link: {file.get('webViewLink')}")
        return file.get('id')

    except HttpError as error:
        print(f"An error occurred: {error}")
        return None

if __name__ == '__main__':
    # Simple CLI wrapper
    if len(sys.argv) < 2:
        print("Usage: python upload_to_drive.py <local_file_path> [drive_filename] [folder_id]")
        print("Example: python upload_to_drive.py report.pdf 'Q2 Report.pdf'")
        sys.exit(1)
        
    local_file = sys.argv[1]
    name_on_drive = sys.argv[2] if len(sys.argv) > 2 else None
    parent_folder = sys.argv[3] if len(sys.argv) > 3 else None
    
    upload_file(local_file, drive_filename=name_on_drive, folder_id=parent_folder)
