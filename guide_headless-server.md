# Server
- Cài đặt Docker thông qua các lệnh:
```
    sudo apt update
    sudo apt install -y docker.io git
    sudo systemctl enable --now docker
```
- Tiếp theo là tạo thư mục để git clone dự án về: 
```
    sudo mkdir -p /opt/gama-models
    sudo chown $USER:$USER /opt/gama-models
    git clone https://github.com/dttrung257/agent_simulation_api
    git clone https://github.com/dhdang2003/pig-farm.git /opt/gama-models/pig-farm
```
- Sử dụng image GAMA Headless chính thức gamaplatform/gama và mở cổng 6868, mount thư mục models:
```
sudo docker run --name gama-server \
  -p 6868:6868 \
  -v /opt/gama-models:/workspace \
  -it gamaplatform/gama \
  /bin/bash -lc "./gama-headless.sh -socket 6868
```
-Xem log bằng: 
```
docker logs -f gama-server 
```
- Khởi động Headless Server sau khi tắt bằng lệnh: 
```
docker start -ai gama-server.
```
- Mở port 6868 trong tường lửa:
```
	sudo ufw allow 6868/tcp
```

# Client
- Cài đặt môi trường ảo Python, kích hoạt môi trường ảo và cài đặt thư viện websockets
```
    python -m venv venv
    source venv/bin/activate   # Windows: venv\Scripts\activate
    pip install websockets
```
- Chạy file test_gamarealtime.py
```
    python test_gamarealtime.py
