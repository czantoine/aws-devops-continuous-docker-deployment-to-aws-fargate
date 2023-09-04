from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello_devops():
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>AWS DevOps Project</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                margin: 0;
                padding: 0;
                background-color: #f4f4f4;
            }
            .container {
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
                text-align: center;
            }
            h1 {
                color: #333;
            }
            p {
                color: #777;
            }
            a {
                color: #00a0d2;
                text-decoration: none;
            }
            .social-icons {
                font-size: 24px;
            }
        </style>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.3/css/all.min.css">
    </head>
    <body>
        <div class="container">
            <h1>AWS DevOps: Continuous Docker Deployment to AWS Fargate from GitHub using Terraform</h1>
            <p>Welcome to the project homepage!</p>
            <p>This project demonstrates the continuous deployment of a Flask app to AWS Fargate using Docker and GitHub.</p>
            <p>Visit my GitHub repository for more information: <a href="https://github.com/Yris-ops" target="_blank">GitHub Repo</a></p>
            <hr>
            <p>Follow me:</p>
            <div class="social-icons">
                <a href="https://www.linkedin.com/in/antoine-cichowicz-837575b1" target="_blank"><i class="fab fa-linkedin"></i></a>
                <a href="https://twitter.com/cz_antoine" target="_blank"><i class="fab fa-twitter"></i></a>
            </div>
        </div>
        <footer style="text-align: center; padding: 10px; background-color: #333; color: #fff;">
            &copy; Copyright: Apache License 2.0 | Antoine CICHOWICZ | Github: Yris Ops
        </footer>
    </body>
    </html>
    '''

if __name__ == "__main__":
    app.run(debug=False)