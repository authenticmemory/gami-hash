package storageprotocol

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
)

var ErrFrameTooLarge = errors.New("protocol frame exceeds maximum size")

type Codec struct {
	reader io.Reader
	writer io.Writer
}

func NewCodec(reader io.Reader, writer io.Writer) *Codec {
	return &Codec{reader: reader, writer: writer}
}

func (c *Codec) ReadRequest() (Request, error) {
	var request Request
	if err := c.readJSON(&request); err != nil {
		return Request{}, err
	}
	if request.Version != Version || request.RequestID == 0 || !request.Operation.Valid() {
		return Request{}, ErrInvalidRequest
	}
	return request, nil
}

func (c *Codec) ReadResponse() (Response, error) {
	var response Response
	if err := c.readJSON(&response); err != nil {
		return Response{}, err
	}
	if response.Version != Version || response.RequestID == 0 || response.OK == (response.Error != nil) {
		return Response{}, ErrInvalidRequest
	}
	return response, nil
}

func (c *Codec) WriteRequest(request Request) error {
	if request.Version != Version || request.RequestID == 0 || !request.Operation.Valid() {
		return ErrInvalidRequest
	}
	return c.writeJSON(request)
}

func (c *Codec) WriteResponse(response Response) error {
	if response.Version != Version || response.RequestID == 0 || response.OK == (response.Error != nil) {
		return ErrInvalidRequest
	}
	return c.writeJSON(response)
}

func (c *Codec) readJSON(value any) error {
	if c.reader == nil {
		return errors.New("protocol reader is unavailable")
	}
	var header [4]byte
	if _, err := io.ReadFull(c.reader, header[:]); err != nil {
		return err
	}
	size := binary.LittleEndian.Uint32(header[:])
	if size == 0 {
		return ErrInvalidRequest
	}
	if size > MaxFrameSize {
		return ErrFrameTooLarge
	}
	payload := make([]byte, int(size))
	if _, err := io.ReadFull(c.reader, payload); err != nil {
		return err
	}
	if err := json.Unmarshal(payload, value); err != nil {
		return fmt.Errorf("decode protocol frame: %w", err)
	}
	return nil
}

func (c *Codec) writeJSON(value any) error {
	if c.writer == nil {
		return errors.New("protocol writer is unavailable")
	}
	payload, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if len(payload) == 0 || len(payload) > MaxFrameSize {
		return ErrFrameTooLarge
	}
	var header [4]byte
	binary.LittleEndian.PutUint32(header[:], uint32(len(payload)))
	if _, err := c.writer.Write(header[:]); err != nil {
		return err
	}
	_, err = c.writer.Write(payload)
	return err
}
